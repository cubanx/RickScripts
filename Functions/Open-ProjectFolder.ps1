function Open-ProjectFolder {
	fd --type directory --exclude node_modules | fzf | ForEach-Object { code $_ }
}

Set-Alias opf Open-ProjectFolder