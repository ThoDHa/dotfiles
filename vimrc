set nocompatible
syntax enable
filetype plugin on

set tabstop=4       " The width of a TAB isset to 4. Still it is a . It is just that Vim will interpret it to be having a width of 4. 
set shiftwidth=4    " Indents will have a width of 4
set softtabstop=4   " Sets the number of columns for a TAB
set smarttab        " let BS delete a tabwidth  
"set expandtab       " Expand TABs tospaces
set autoindent      " set auto indent
set smartindent     " Auto indent new lines

set ignorecase      " ignore cases in searches
set smartcase       " turn off ignorecase if there is caps in search

set scrolloff=5     " Keep a buffer of 5 lines around insert
set background=dark " set background to dark
set number          " set number to show
set relativenumber  " set the number to be relative
set nowrap          " don't wrap lines
set wildmenu

"set noswapfile      " no swap file
"set nobackup        " don't create a backup file

set backupdir=~/.vim/tmp//
set directory=~/.vim/tmp//
set undodir=/.vim/tmp//

set clipboard=unnamedplus " Set to use system clipboard for linux, only works with vim-gtk because it's compiled with clipboard support

colorscheme codedark 

" File browser
let g:netrw_banner=0				" hides the top banner by default
let g:netrw_liststyle=3				" Tree view
let g:netrw_browse_split=4			" Open files in pervious window
let g:netrw_altv=0				" Switches the NetRW display to the right 
let g:netrw_winsize=90				" Limit NetRW to 15% of the screen
let g:netrw_keepdir=0				" keeps the directory you accessed previously
let g:netrw_localcopydircmd='cp -r' " Modify commands to copy folders recursively


" Finding Files:
" Search down into subfolders
" Provides tab-compiletion for all file-related paths
set path+=**
"set rtp+=/usr/bin/fzf
" Display all matching files when we tab compilete
set wildmenu

" NOW WE CAN:
" - HIt tab to :find by partial match
"   - Use * to make it fuzzy
"
" THINGS TO CONSIDER:
" - :b lets you autocomplete any open buffer


" TAG JUMPING:

" Create the `tags` file (may need to install ctags first)
" NOW WE CAN:
" - Use ^] to jump to tag under cursor
" - Use g^] for ambiguous tags
" - Use ^t to jump back up the tag stack

" THINGS TO CONSIDER:
" - This doesn't help if you want a visual list of tags

" Load all plugins now.
" Plugins need to be added to runtimepath before helptags can be generated.
packloadall
" Load all of the helptags now, after plugins have been loaded.
" All messages and errors will be ignored.
silent! helptags ALL
