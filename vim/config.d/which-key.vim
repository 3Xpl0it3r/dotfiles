nnoremap <silent> <leader> :silent WhichKey ','<CR>
vnoremap <silent> <leader> :silent <c-u> :silent WhichKeyVisual ','<CR>

let g:which_key_map =  {}
let g:which_key_sep = ': '
" Set a shorter timeout, default is 1000
set timeoutlen=100

let g:which_key_use_floating_win = 1

" Single mappings
let g:which_key_map['/'] = [ '<Plug>NERDCommenterToggle'                                , 'comment'      ]
let g:which_key_map['f'] = [ ':Files'                                                   , 'search files' ]
let g:which_key_map['T'] = [ ':Rg'                                                      , 'search text'  ]
let g:which_key_map['g'] = [ ':FloatermNew --width=0.9 --height=0.9 lazygit'            , 'git'          ]
let g:which_key_map['t'] = [ ':FloatermNew'                                             , 'terminal'     ]
let g:which_key_map['v'] = [ '<C-W>v'                                                   , 'split right'  ]

" s is for search
let g:which_key_map.s = {
      \ 'name' : '+检索' ,
      \ 'b' : [':CocFzfList snippets'                                   , 'snippets/block'],
      \ 'e' : [':CocFzfList diagnostics'                                , 'diagnostics'],
      \ 'g' : [':GFiles'                                                , 'git files'],
      \ 'G' : [':GFiles?'                                               , 'modified git files'],
      \ 'M' : [':Maps'                                                  , 'normal maps'] ,
      \ 's' : [':CocFzfList outline'                                    , 'cur symbols'],
      \ 'S' : [':CocFzfList symbols'                                    , 'root symbols'],
      \ 't' : [':Rg'                                                    , 'Rg text'],
      \ 'w' : [':Windows'                                               , 'search windows'],
      \ 'z' : [':FloatermNew --width=0.8 --height=0.8 fzf --reverse'    , 'FZF'],
      \ }

" P is for vim-plug
let g:which_key_map.p = {
      \ 'name' : '+插件' ,
      \ 'i' : [':PlugInstall'              , 'install'],
      \ 'u' : [':PlugUpdate'               , 'update'],
      \ 'c' : [':PlugClean'                , 'clean'],
      \ 's' : [':source ~/.vim/vimrc', 'source vimrc'],
      \ }

" Register which key map
call which_key#register(',', "g:which_key_map")

