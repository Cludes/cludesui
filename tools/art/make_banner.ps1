# Renders tools/art/banner.html into the options-window banner PNGs (white on
# transparent) in CludesUI/media/icons/sidebar. New files need a full game restart.
$chrome = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
$art = $PSScriptRoot
$out = Join-Path $art "..\..\CludesUI\media\icons\sidebar"
$page = "file:///" + ((Join-Path $art "banner.html") -replace '\\', '/')
$layers = @(
    @{ name = "logo"; file = "rail-logo.png"; size = "128,128" },
    @{ name = "word"; file = "banner-word.png"; size = "440,88" },
    @{ name = "accent"; file = "banner-accent.png"; size = "440,88" }
)
foreach ($l in $layers) {
    $target = Join-Path $out $l.file
    Start-Process -FilePath $chrome -NoNewWindow -Wait -ArgumentList @(
        '--headless', '--disable-gpu', '--hide-scrollbars', '--default-background-color=00000000',
        '--allow-file-access-from-files', '--virtual-time-budget=2000',
        "--screenshot=$target", "--window-size=$($l.size)", "$page`?layer=$($l.name)")
    Write-Output "$($l.file): $((Get-Item $target).Length) bytes"
}
