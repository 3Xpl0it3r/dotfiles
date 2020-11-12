call plug#begin('~/.vim/plugged')
Plug 'ryanoasis/vim-devicons'

"dashboard
Plug 'mhinz/vim-startify'

" 多行编辑
Plug 'mg979/vim-visual-multi', {'branch': 'master'}

Plug 'luochen1990/rainbow'
" 批量注释
Plug 'preservim/nerdcommenter'

Plug 'tpope/vim-unimpaired' 

Plug 'easymotion/vim-easymotion'

Plug 'fatih/vim-go'

Plug 'mbbill/undotree'
Plug 'voldikss/vim-floaterm'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes' "airline 的主题

Plug 'jiangmiao/auto-pairs'
Plug 'Yggdroot/indentLine'
"
Plug 'neoclide/coc.nvim', {'branch': 'master', 'do': 'yarn install --frozen-lockfile'}

"
"主题

Plug 'doums/darcula'
Plug 'morhetz/gruvbox'
Plug 'Rigellute/shades-of-purple.vim'

" 函数列举
" Plug 'liuchengxu/vista.vim'

" which key
Plug 'liuchengxu/vim-which-key'

Plug 'tpope/vim-surround'
"
" markdown渲染
Plug 'iamcco/markdown-preview.nvim', { 'do': { -> mkdp#util#install() }, 'for': ['markdown', 'vim-plug']}


" 调试插件
Plug 'puremourning/vimspector'


"fzf
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'antoinemadec/coc-fzf'

"
" 统计
Plug 'wakatime/vim-wakatime'


call plug#end()


