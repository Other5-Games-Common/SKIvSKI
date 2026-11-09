# Unreal MCP from PowerShell (plain JSON-RPC to http://localhost:8000/mcp, the editor must be open), plus the
# helpers the SKIvSKI graph scripts use. Dot-source it from this folder: . ./UnrealMcp.ps1
# Py runs an editor Python file through the editor's console box (the "Cmd" textbox, ref tb3 in the main window);
# AddVars / AddFunctions / WriteDslFn build Blueprints; OpenBpWindow / SelectEvent / AddParam / SetRpc drive the
# Blueprint editor's UI for what the DSL can't do (custom event inputs and Replicates).
$script:McpUrl = 'http://localhost:8000/mcp'
$script:McpSession = $null
$script:McpId = 0

function Mcp-Post($body) {
	$headers = @{ 'Accept' = 'application/json, text/event-stream' }
	if ($script:McpSession) { $headers['Mcp-Session-Id'] = $script:McpSession }
	$json = $body | ConvertTo-Json -Depth 40 -Compress
	$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
	$resp = Invoke-WebRequest -Uri $script:McpUrl -Method Post -Body $bytes -ContentType 'application/json' -Headers $headers -UseBasicParsing -TimeoutSec 600
	if ($resp.Headers['Mcp-Session-Id']) { $script:McpSession = $resp.Headers['Mcp-Session-Id'] }
	$text = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
	if ($text -match '^\s*(event:|data:)') {
		$lines = $text -split "`n" | Where-Object { $_ -like 'data:*' } | ForEach-Object { $_.Substring(5).Trim() }
		$text = $lines[-1]
	}
	return $text
}

function Mcp-Init {
	$script:McpId++
	$null = Mcp-Post @{ jsonrpc = '2.0'; id = $script:McpId; method = 'initialize'; params = @{ protocolVersion = '2025-03-26'; capabilities = @{}; clientInfo = @{ name = 'ps'; version = '1' } } }
	$null = Mcp-Post @{ jsonrpc = '2.0'; method = 'notifications/initialized' }
}

function Mcp-Raw($method, $params) {
	if (-not $script:McpSession) { Mcp-Init }
	$script:McpId++
	return Mcp-Post @{ jsonrpc = '2.0'; id = $script:McpId; method = $method; params = $params }
}

function Mcp-Tool($name, $arguments) {
	$r = Mcp-Raw 'tools/call' @{ name = $name; arguments = $arguments } | ConvertFrom-Json
	if ($r.error) { return "RPCERROR: " + ($r.error | ConvertTo-Json -Depth 10) }
	return ($r.result.content | ForEach-Object { $_.text }) -join "`n"
}

function Mcp-Call($toolset, $tool, $arguments) {
	if (-not $arguments) { $arguments = @{} }
	return Mcp-Tool 'call_tool' @{ toolset_name = $toolset; tool_name = $tool; arguments = $arguments }
}

$script:BP = 'editor_toolset.toolsets.blueprint.BlueprintTools'

# Runs an editor Python file through the console box (tb3 in the main window) and returns its log lines.
# The script gets a unique marker as sys.argv[1], prints "CLAUDE|<marker>|..." lines and finally "CLAUDE|<marker>|END".
function Py($file, $timeoutSec = 180) {
	$marker = 'm' + [guid]::NewGuid().ToString('N').Substring(0, 8)
	$S = 'SlateInspectorToolset.SlateInspectorToolset'
	$null = Mcp-Call $S 'Type' @{ ref = 'tb3'; text = ('py "' + $file.Replace([char]92, [char]47) + '" ' + $marker); submit = $true }
	$deadline = (Get-Date).AddSeconds($timeoutSec)
	$text = ''
	while ((Get-Date) -lt $deadline) {
		Start-Sleep -Milliseconds 700
		$r = (Mcp-Call 'EditorToolset.LogsToolset' 'GetLogEntries' @{ category = ''; pattern = "CLAUDE\|$marker\|"; maxEntries = 600 } | ConvertFrom-Json).returnValue
		$text = ($r | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.message } }) -join "`n"
		if ($text -match "CLAUDE\|$marker\|END") { break }
	}
	if ($text -notmatch "CLAUDE\|$marker\|END") { $text = "TIMEOUT`n" + $text }
	$text -split "`n" | ForEach-Object { $_ -replace ('^.*CLAUDE\|' + $marker + '\|'), '' }
}

function GraphRef($bpPath, $graph = 'EventGraph') { $n = $bpPath.Split('/')[-1]; return @{ refPath = "$bpPath.$($n):$graph" } }
function Types($bpPath, [string[]]$filters, $n = 10) {
	$g = GraphRef $bpPath
	foreach ($f in $filters) {
		$r = (Mcp-Call $script:BP 'find_node_types' @{ graph = $g; type_id_filter = $f; context_pins = @() } | ConvertFrom-Json).returnValue
		"$f => " + (($r | Select -First $n | % { if ($_ -is [string]) { $_ } else { $_.type_id } }) -join ' ; ')
	}
}
function Pins($bpPath, [string[]]$typeIds) {
	$g = GraphRef $bpPath
	foreach ($t in $typeIds) {
		$r = (Mcp-Call $script:BP 'get_node_type_pins' @{ graph = $g; type_id = $t } | ConvertFrom-Json).returnValue
		$in = ($r.input_pins | % { "$($_.name):$($_.type_id)=$($_.value)" }) -join ', '
		$out = ($r.output_pins | % { "$($_.name):$($_.type_id)" }) -join ', '
		"$t`n   IN  $in`n   OUT $out"
	}
}

# $vars: array of @(name, type, category, replication('None'|'Replicated'|'RepNotify'), editable(bool))
function AddVars($bpPath, $vars) {
	$n = $bpPath.Split('/')[-1]; $bp = @{ refPath = "$bpPath.$n" }
	$existing = Mcp-Call $script:BP 'list_variables' @{ blueprint = $bp }
	foreach ($v in $vars) {
		$name, $type, $cat, $rep, $edit = $v
		if ($existing -notmatch ('"' + $name + '"')) {
			if ($type -like '/*') {
				if ($type -like '*:Array') { $r = Mcp-Call $script:BP 'add_object_variable' @{ blueprint = $bp; name = $name; object_class = @{ refPath = $type.Replace(':Array','') }; container_type = 'ARRAY' } }
				elseif ($type -like '*Struct*' -or $type -like '/Script/CoreUObject.*' -or $type -like '/Script/Engine.HitResult') { $r = Mcp-Call $script:BP 'add_struct_variable' @{ blueprint = $bp; name = $name; struct_type = @{ refPath = $type } } }
				else { $r = Mcp-Call $script:BP 'add_object_variable' @{ blueprint = $bp; name = $name; object_class = @{ refPath = $type } } }
			} elseif ($type -like '*:Array') { $r = Mcp-Call $script:BP 'add_variable' @{ blueprint = $bp; name = $name; type_name = $type.Replace(':Array',''); container_type = 'ARRAY' } }
			else { $r = Mcp-Call $script:BP 'add_variable' @{ blueprint = $bp; name = $name; type_name = $type } }
			if ($r -match 'rror') { "ERR $name : $r" }
		}
		$null = Mcp-Call $script:BP 'set_variable_category' @{ blueprint = $bp; variable_name = $name; category = $cat }
		if ($rep -and $rep -ne 'None') { $null = Mcp-Call $script:BP 'set_variable_replication' @{ blueprint = $bp; variable_name = $name; replication = $rep } }
		if ($edit) { $null = Mcp-Call $script:BP 'set_variable_instance_editable' @{ blueprint = $bp; variable_name = $name; instance_editable = $true } }
	}
	"vars done: " + $vars.Count
}

function Dsl($bpPath, $file, $graph = 'EventGraph') {
	$code = [System.IO.File]::ReadAllText($file).Replace("`r`n", "`n")
	Mcp-Call $script:BP 'write_graph_dsl' @{ graph = (GraphRef $bpPath $graph); code = $code }
}
function Compile($bpPath) {
	$n = $bpPath.Split('/')[-1]
	Mcp-Call $script:BP 'compile_blueprint' @{ blueprint = @{ refPath = "$bpPath.$n" }; warnings_as_errors = $false }
}

$script:SI = 'SlateInspectorToolset.SlateInspectorToolset'
function Snap($ref, $depth = 90) { (Mcp-Call $script:SI 'Snapshot' @{ ref = $ref; maxDepth = $depth } | ConvertFrom-Json).returnValue -split "`n" }
function RefOf($line) { if ($line -match '\[ref=([a-z]+\d+)\]') { return $Matches[1] } }
function UiClick($ref) { $null = Mcp-Call $script:SI 'Hover' @{ ref = $ref }; return (Mcp-Call $script:SI 'Click' @{ ref = $ref } | ConvertFrom-Json).returnValue }
# Opens a Blueprint editor and returns its window ref.
function OpenBpWindow($assetPath) {
	$name = $assetPath.Split('/')[-1]
	$null = Mcp-Call 'EditorToolset.EditorAppToolset' 'OpenEditorForAsset' @{ assetPath = $assetPath }
	Start-Sleep 2
	$wins = Snap '' 1
	$line = $wins | Where-Object { $_ -match ('^window "' + $name + '"') } | Select-Object -First 1
	$w = RefOf $line
	$list = (Mcp-Call $script:SI 'Windows' @{} | ConvertFrom-Json).returnValue | ConvertFrom-Json
	$idx = ($list | Where-Object { $_.title -eq $name } | Select-Object -First 1).index
	$null = Mcp-Call $script:SI 'Windows' @{ action = 'select'; index = $idx }
	$null = Mcp-Call $script:SI 'Observe' @{ ref = $w; maxDepth = 90 }
	Start-Sleep 1
	return $w
}
# Selects a custom event in My Blueprint (expanding EventGraph first) so the Details panel shows it.
function SelectEvent($w, $eventName) {
	$s = Snap $w
	$item = $s | Where-Object { $_ -match ('listitem "' + [regex]::Escape($eventName) + '"') } | Select-Object -First 1
	if (-not $item) {
		$i = ($s | Select-String 'listitem "EventGraph"' | Select-Object -First 1).LineNumber
		$btn = RefOf $s[$i]
		$null = UiClick $btn
		Start-Sleep 1
		$s = Snap $w
		$item = $s | Where-Object { $_ -match ('listitem "' + [regex]::Escape($eventName) + '"') } | Select-Object -First 1
	}
	if (-not $item) { return "no item $eventName" }
	$null = UiClick (RefOf $item)
	Start-Sleep 1
	return "selected $eventName"
}
# mode: 'Not Replicated' | 'Multicast' | 'Run on Server' | 'Run on owning Client'
function SetRpc($w, $mode, [bool]$reliable) {
	$s = Snap $w
	$i = ($s | Select-String 'text "Replicates"' | Select-Object -First 1).LineNumber
	if (-not $i) { return 'no Replicates row' }
	$combo = RefOf $s[$i]
	$null = Mcp-Call $script:SI 'SelectOption' @{ ref = $combo; value = $mode }
	Start-Sleep 1
	$s = Snap $w
	$cbLine = $s | Where-Object { $_ -match 'checkbox "Reliable"' } | Select-Object -First 1
	$isChecked = $cbLine -match '\bchecked\b' -and $cbLine -notmatch 'unchecked'
	if ($reliable -ne $isChecked) { $null = UiClick (RefOf $cbLine) }
	Start-Sleep 1
	$s = Snap $w
	return ($s | Where-Object { $_ -match 'checkbox "Reliable"' } | Select-Object -First 1)
}
# Adds an input to the selected event: name and type (as listed in the type picker: Boolean, Integer, Float, Vector, ...).
function AddParam($w, $pname, $ptype) {
	$s = Snap $w
	$i = ($s | Select-String 'text "Inputs"' | Select-Object -First 1).LineNumber
	if (-not $i) { return 'no Inputs' }
	$plus = RefOf $s[$i]          # the + button follows the "Inputs" text
	$null = UiClick $plus
	Start-Sleep 1
	$s = Snap $w
	# the new row is the last "NewParam" textbox
	$tbLines = $s | Select-String 'textbox "NewParam' | Select-Object -Last 1
	if (-not $tbLines) { return 'no NewParam row' }
	$j = $tbLines.LineNumber
	$inner = RefOf $s[$j]
	$null = Mcp-Call $script:SI 'Type' @{ ref = $inner; text = ''; submit = $false }
	1..12 | ForEach-Object { $null = Mcp-Call $script:SI 'PressKey' @{ key = 'BackSpace' } }
	$null = Mcp-Call $script:SI 'Type' @{ ref = $inner; text = $pname; submit = $true }
	Start-Sleep 1
	$s = Snap $w
	$row = ($s | Select-String ('textbox "' + $pname + '"') | Select-Object -Last 1).LineNumber
	$combo = $null
	for ($k = $row; $k -lt $row + 6; $k++) { if ($s[$k] -match 'combobox') { $combo = RefOf $s[$k]; break } }
	$null = UiClick $combo
	Start-Sleep 1
	$wins = Snap '' 1
	$pop = RefOf (($wins | Where-Object { $_ -match '^window \[pos' }) | Where-Object { $_ -notmatch 'size=1\d\d,50' } | Select-Object -First 1)
	$null = Mcp-Call $script:SI 'Observe' @{ ref = $pop; maxDepth = 40 }
	Start-Sleep 1
	$ps = Snap $pop 40
	$opt = $ps | Where-Object { $_ -match ('generic "' + $ptype + '"') } | Select-Object -First 1
	if (-not $opt) { return "type $ptype not in list" }
	$null = UiClick (RefOf $opt)
	Start-Sleep 1
	return "param $pname : $ptype"
}
function DeleteNodes($bpPath, $graph = 'EventGraph', [string[]]$keepTitles = @()) {
	$g = GraphRef $bpPath $graph
	$nodes = (Mcp-Call $script:BP 'find_nodes' @{ graph = $g; title = '' } | ConvertFrom-Json).returnValue
	$keepRefs = @()
	foreach ($t in $keepTitles) { $keepRefs += ((Mcp-Call $script:BP 'find_nodes' @{ graph = $g; title = $t; entry_points_only = $true } | ConvertFrom-Json).returnValue | ForEach-Object { $_.refPath }) }
	$n = 0
	foreach ($node in $nodes) { if ($keepRefs -notcontains $node.refPath -and $node.refPath -notmatch "ComponentBoundEvent") { $null = Mcp-Call $script:BP 'delete_node' @{ node = $node }; $n++ } }
	"deleted $n nodes, kept $($keepRefs.Count)"
}

# Splits a DSL file into top-level forms (with the comment lines right before each), returns objects {Kind, Name, Code}.
function DslForms($file) {
	$text = [System.IO.File]::ReadAllText($file).Replace("`r`n", "`n")
	$forms = @(); $depth = 0; $start = -1; $inStr = $false; $inComment = $false; $pending = ''
	$lineStart = 0
	for ($i = 0; $i -lt $text.Length; $i++) {
		$c = $text[$i]
		if ($inComment) { if ($c -eq "`n") { $inComment = $false }; continue }
		if ($inStr) { if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $inStr = $false }; continue }
		if ($c -eq ';') { $inComment = $true; continue }
		if ($c -eq '"') { $inStr = $true; continue }
		if ($c -eq '(') { if ($depth -eq 0) { $start = $i }; $depth++ }
		elseif ($c -eq ')') { $depth--; if ($depth -eq 0) {
			$code = $text.Substring($start, $i - $start + 1)
			if ($code -match '^\(\s*(fn|event)\s+([^\s\(\)]+)') { $forms += [pscustomobject]@{ Kind = $Matches[1]; Name = $Matches[2]; Code = $code } }
		} }
	}
	return $forms
}
function WriteDsl($bpPath, $file) {
	foreach ($f in (DslForms $file)) {
		$graph = if ($f.Kind -eq 'fn') { $f.Name } else { 'EventGraph' }
		$r = Mcp-Call $script:BP 'write_graph_dsl' @{ graph = (GraphRef $bpPath $graph); code = $f.Code }
		"$($f.Kind) $($f.Name): $r"
	}
}
# $fns: @(@('Name', @(@('Param','float'), ...)), ...)
function AddFunctions($bpPath, $fns) {
	$n = $bpPath.Split('/')[-1]; $asset = @{ refPath = "$bpPath.$n" }
	foreach ($fn in $fns) {
		$name = $fn[0]
		$g = (Mcp-Call $script:BP 'add_function_graph' @{ blueprint = $asset; graph_name = $name } | ConvertFrom-Json).returnValue
		foreach ($p in $fn[1]) {
			$isIn = ($p.Count -lt 3 -or $p[2] -ne "out")
			if ($p[1] -like "obj:*") { $r = Mcp-Call $script:BP "add_object_function_param" @{ graph = $g; param_name = $p[0]; object_class = @{ refPath = $p[1].Substring(4) }; input_param = $isIn } }
			elseif ($p[1] -like "struct:*") { $r = Mcp-Call $script:BP "add_struct_function_param" @{ graph = $g; param_name = $p[0]; struct_type = @{ refPath = $p[1].Substring(7) }; input_param = $isIn } }
			else { $r = Mcp-Call $script:BP "add_function_param" @{ graph = $g; param_name = $p[0]; param_type = $p[1]; input_param = $isIn } }
			if ($r -match "rror") { "  ERR $($p[0]): $r" }
		}
		"fn $name"
	}
}

function ClearFn($bpPath, $graph) {
	$g = GraphRef $bpPath $graph
	$nodes = (Mcp-Call $script:BP 'find_nodes' @{ graph = $g; title = '' } | ConvertFrom-Json).returnValue
	foreach ($node in $nodes) { if ($node.refPath -notmatch 'K2Node_FunctionEntry|K2Node_FunctionResult') { $null = Mcp-Call $script:BP 'delete_node' @{ node = $node } } }
}
function WriteDslFn($bpPath, $file, [string[]]$only = @()) {
	foreach ($f in (DslForms $file)) {
		if ($only.Count -gt 0 -and $only -notcontains $f.Name) { continue }
		$graph = if ($f.Kind -eq 'fn') { $f.Name } else { 'EventGraph' }
		if ($f.Kind -eq 'fn') { ClearFn $bpPath $graph }
		$r = Mcp-Call $script:BP 'write_graph_dsl' @{ graph = (GraphRef $bpPath $graph); code = $f.Code }
		"$($f.Kind) $($f.Name): $r"
	}
}

function SaveAll() { Mcp-Call 'editor_toolset.toolsets.asset.AssetTools' 'save_assets' @{ asset_paths = @('/SKIvSKI') } }
function SaveAssets([string[]]$paths) { Mcp-Call 'editor_toolset.toolsets.asset.AssetTools' 'save_assets' @{ asset_paths = $paths } }
function SaveSki() { Py (Join-Path $PSScriptRoot "SaveSki.py") }
function RunGame($map, $script, $name, $extra = @(), $timeoutMs = 240000) {
	$sp = Join-Path $env:TEMP 'SKIvSKI'; New-Item -ItemType Directory -Force $sp | Out-Null
	$log = "$sp\$name.log"; if (Test-Path $log) { Remove-Item $log }
	$args = @("`"$(ProjectFile)`"", $map, '-game', '-windowed', '-ResX=1280', '-ResY=720', '-log', "-abslog=`"$log`"", "-Other5TestScript=`"$script`"", '-NoEOS') + $extra
	$p = Start-Process -FilePath (EditorExe) -ArgumentList $args -PassThru
	$p.WaitForExit($timeoutMs) | Out-Null
	if (-not $p.HasExited) { "STILL RUNNING" }
	Select-String -Path $log -Pattern 'SKI\||OTHER5TEST\| (LOG|FAIL|PASS|DONE)|Blueprint Runtime Error|Accessed None|Script Stack|Infinite loop' | ForEach-Object { $_.Line -replace '^\[[^\]]*\]\[[^\]]*\]\w+: (Display: )?(\[[^\]]*\] )?', '' }
}

function NewNode($graph, $typeId, $x, $y) {
	return (Mcp-Call $script:BP 'create_node' @{ graph = $graph; type_id = $typeId; pos = @{ x = $x; y = $y } } | ConvertFrom-Json).returnValue
}
function NodeInfo($node) { return ((Mcp-Call $script:BP 'get_node_infos' @{ nodes = @($node) } | ConvertFrom-Json).returnValue)[0] }
function PinId($node, $name, $dir) {
	$info = NodeInfo $node
	$pins = if ($dir -eq 'out') { $info.output_pins } else { $info.input_pins }
	$p = $pins | Where-Object { $_.name -eq $name } | Select-Object -First 1
	if (-not $p) { throw "no $dir pin $name on $($node.refPath): " + (($pins | ForEach-Object { $_.name }) -join ',') }
	return $p.pin_id
}
function Link($fromNode, $fromPin, $toNode, $toPin) {
	Mcp-Call $script:BP 'connect_pins' @{ output_pin = (PinId $fromNode $fromPin 'out'); input_pin = (PinId $toNode $toPin 'in') }
}

# The project file and the launcher engine's editor (from the uproject's EngineAssociation, via the registry).
function ProjectFile() { return (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\Other5.uproject')).Path }
function EditorExe() {
	$assoc = (Get-Content (ProjectFile) -Raw | ConvertFrom-Json).EngineAssociation
	$dir = (Get-ItemProperty "HKLM:\SOFTWARE\EpicGames\Unreal Engine\$assoc").InstalledDirectory
	return (Join-Path $dir 'Engine\Binaries\Win64\UnrealEditor.exe')
}

# Removes the selected event's inputs whose names start with $prefix (the row's remove button, after the type boxes).
function RemoveParamsLike($w, $prefix) {
	for ($n = 0; $n -lt 12; $n++) {
		$s = Snap $w
		$hit = $s | Select-String ('textbox "' + [regex]::Escape($prefix)) | Select-Object -First 1
		if (-not $hit) { return "removed $n" }
		$btn = $null
		for ($k = $hit.LineNumber; $k -lt $hit.LineNumber + 16; $k++) {
			if ($s[$k] -match '^\s*button \[pos' -and $s[$k - 1] -match 'image' -and $s[$k - 2] -match 'button \[pos' -and $s[$k - 3] -match 'combobox') { $btn = RefOf $s[$k]; break }
		}
		if (-not $btn) { return "no remove button" }
		$null = UiClick $btn
		Start-Sleep 1
	}
}
