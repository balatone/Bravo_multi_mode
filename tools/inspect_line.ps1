param(
  [string]$FilePath,
  [int]$LineNumber
)
$lines = Get-Content -Path $FilePath -Encoding UTF8
if ($LineNumber -lt 1 -or $LineNumber -gt $lines.Count) { Write-Output "Line out of range"; exit 1 }
$line = $lines[$LineNumber-1]
Write-Output "Line $LineNumber: [$line]"
$chars = $line.ToCharArray()
for ($i=0; $i -lt $chars.Length; $i++) {
  $c = $chars[$i]
  $code = [int][char]$c
  Write-Output ("{0,3}: 0x{1:X2} ({1}) '{2}'" -f ($i+1), $code, $c)
}

# Also show preceding and following lines for context
if ($LineNumber -gt 1) { Write-Output "Prev: $($lines[$LineNumber-2])" }
if ($LineNumber -lt $lines.Count) { Write-Output "Next: $($lines[$LineNumber])" }
