" vim-kompleter - Smart keyword completion for Vim
" Maintainer:   Szymon Wrozynski
" Version:      0.1.8
"
" Installation:
" Place in ~/.vim/plugin/kompleter.vim or in case of Pathogen:
"
"     cd ~/.vim/bundle
"     git clone https://github.com/szw/vim-kompleter.git
"
" In case of Vundle:
"
"     Bundle "szw/vim-kompleter"
"
" License:
" Copyright (c) 2013 Szymon Wrozynski and Contributors.
" Distributed under the same terms as Vim itself.
" See :help license
"
" Usage:
" help :kompleter
" https://github.com/szw/vim-kompleter/blob/master/README.md

if exists("g:loaded_kompleter") || &cp || v:version < 700 || !has("ruby")
  finish
endif

let g:loaded_kompleter = 1

" Set to 0 disable asynchronous mode (using forking).
if !exists("g:kompleter_async_mode")
  let g:kompleter_async_mode = 1
endif

" 0 - case insensitive
" 1 - case sensitive
" 2 - smart case sensitive (see :help 'smartcase')
if !exists("g:kompleter_case_sensitive")
  let g:kompleter_case_sensitive = 1
endif

if !exists("g:kompleter_replace_standard_mappings")
  let g:kompleter_replace_standard_mappings = 1
endif

if g:kompleter_replace_standard_mappings
  inoremap <C-p> <C-x><C-u><C-p><C-p>
  inoremap <C-n> <C-x><C-u>
endif

au VimEnter * call s:startup()
au VimLeave * call s:cleanup()

fun! s:prepare_buffer()
  let &completefunc = "kompleter#Complete"
  let &l:completefunc = "kompleter#Complete"
  call s:process_keywords()
endfun

fun! s:process_keywords()
  ruby KOMPLETER.process_all
endfun

fun! s:expire_buffer(number)
  ruby KOMPLETER.expire_buffer(VIM.evaluate("a:number").to_i)
endfun

fun! s:cleanup()
  ruby KOMPLETER.stop_data_server
endfun

fun! s:startup()
  au BufEnter,BufRead * call s:prepare_buffer()
  au CursorHold,InsertLeave * call s:process_keywords()
  au BufUnload * call s:expire_buffer(expand('<abuf>'))
  ruby KOMPLETER.start_data_server
  call s:prepare_buffer()
endfun

fun! s:all_visibles()
  let buflist = []

  for i in range(tabpagenr('$'))
    call extend(buflist, tabpagebuflist(i + 1))
  endfor

  return buflist
endfun

fun! kompleter#Complete(find_start_column, base)
  if a:find_start_column
    ruby VIM.command("return #{KOMPLETER.find_start_column}")
  else
    ruby VIM.command("return [#{KOMPLETER.complete(VIM.evaluate("a:base")).map { |c| "{ 'word': '#{c}', 'dup': 1 }" }.join(", ") }]")
  endif
endfun

let s:kompleter_folder = fnamemodify(resolve(expand('<sfile>:p')), ':h')

ruby << EOF
require "pathname"
require Pathname.new(VIM.evaluate("s:kompleter_folder")).parent.join("ruby", "kompleter").to_s
EOF
