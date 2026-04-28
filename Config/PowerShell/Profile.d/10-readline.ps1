Set-PSReadLineKeyHandler -Key Escape -Function RevertLine
Set-PSReadLineKeyHandler -Key Alt+RightArrow -Function ForwardWord
Set-PSReadLineKeyHandler -Key Alt+LeftArrow -Function BackwardWord

Set-PSReadLineOption -PredictionViewStyle ListView
