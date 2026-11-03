param([int]$X, [int]$Y, [string]$Action = 'click', [int]$Wheel = 0)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Input32 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out P p);
  [StructLayout(LayoutKind.Sequential)] public struct P { public int X; public int Y; }
}
"@
$pt = New-Object Input32+P
[void][Input32]::GetCursorPos([ref]$pt)
Write-Output ("CURSOR_BEFORE " + $pt.X + "," + $pt.Y)
[void][Input32]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 250
if ($Wheel -ne 0) {
  [Input32]::mouse_event(0x0800, 0, 0, [uint32]($Wheel), [IntPtr]::Zero)
  Write-Output ("WHEEL " + $Wheel)
} else {
  [Input32]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  [Input32]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  Write-Output ("CLICK " + $X + "," + $Y)
}
$pt2 = New-Object Input32+P
[void][Input32]::GetCursorPos([ref]$pt2)
Write-Output ("CURSOR_AFTER " + $pt2.X + "," + $pt2.Y)
