set number relativenumber

" Use four spaces for indentation by default.
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4

" Make recipes require literal tabs; keep their conventional width.
augroup makefile_indentation
  autocmd!
  autocmd FileType make setlocal noexpandtab tabstop=8 shiftwidth=8 softtabstop=0
augroup END
