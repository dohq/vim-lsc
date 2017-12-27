if !exists('s:initialized')
  let s:find_actions_id = 1
  let s:rename_id = 1
  let s:initialized = v:true
endif

function! lsc#edit#findCodeActions(...) abort
  if a:0 > 0
    let ActionFilter = a:1
  else
    let ActionFilter = function("<SID>ActionMenu")
  endif
  call lsc#file#flushChanges()
  let s:find_actions_id += 1
  let old_pos = getcurpos()
  let find_actions_id = s:find_actions_id
  function! SelectAction(result) closure abort
    if !s:isFindActionsValid(old_pos, find_actions_id)
      call lsc#message#show('Actions ignored')
      return
    endif
    if type(a:result) != v:t_list || len(a:result) == 0
      call lsc#message#show('No actions available')
      return
    endif
    let choice = ActionFilter(a:result)
    if type(choice) == v:t_dict
      call lsc#server#userCall('workspace/executeCommand',
          \ {'command': choice['command'],
          \ 'arguments': choice['arguments']},
          \ {_->0})
    endif
  endfunction
  call lsc#server#userCall('textDocument/codeAction',
      \ s:TextDocumentRangeParams(), function('SelectAction'))
endfunction

" TODO - handle visual selection for range
function! s:TextDocumentRangeParams() abort
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'range': {
      \   'start': {'line': line('.') - 1, 'character': col('.') - 1},
      \   'end': {'line': line('.') - 1, 'character': col('.')}},
      \ 'context': {'diagnostics': []}
      \}
endfunction

function! s:ActionMenu(actions)
  let choices = ['Choose an action:']
  let idx = 0
  while idx < len(a:actions)
    call add(choices, string(idx+1).' - '.a:actions[idx]['title'])
    let idx += 1
  endwhile
  let choice = inputlist(choices)
  if choice > 0
    return a:actions[choice - 1]
  endif
  return v:false
endfunction

function! s:isFindActionsValid(old_pos, find_actions_id) abort
  return a:find_actions_id == s:find_actions_id &&
      \ a:old_pos == getcurpos()
endfunction

function! lsc#edit#rename(...) abort
  call lsc#file#flushChanges()
  if a:0 >= 1
    let new_name = a:1
  else
    let new_name = input('Enter a new name: ')
  endif
  let s:rename_id += 1
  let old_pos = getcurpos()
  let rename_id = s:rename_id
  function! ApplyEdit(result) closure abort
    if !s:isRenameValid(old_pos, rename_id)
      call lsc#message#show('Rename ignored')
      return
    endif
    call lsc#edit#apply(a:result)
  endfunction
  let params = s:TextDocumentPositionParams()
  let params.newName = new_name
  call lsc#server#userCall('textDocument/rename', params, function('ApplyEdit'))
endfunction

function! s:TextDocumentPositionParams() abort
  return { 'textDocument': {'uri': lsc#uri#documentUri()},
      \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
      \ }
endfunction

function! s:isRenameValid(old_pos, rename_id) abort
  return a:rename_id == s:rename_id &&
      \ a:old_pos == getcurpos()
endfunction


" Applies a workspace edit and returns `v:true` if it was successful.
function! lsc#edit#apply(workspace_edit) abort
  if !exists('g:lsc_enable_apply_edit')
      \ || !g:lsc_enable_apply_edit
      \ || !has_key(a:workspace_edit, 'changes')
    return v:false
  endif
  let view = winsaveview()
  let old_paste = &paste
  set paste
  let alternate=@#
  let old_buffer = bufnr('%')

  call s:ApplyAll(a:workspace_edit.changes)

  if old_buffer != bufnr('%') | execute 'buffer' old_buffer | endif
  if len(alternate) > 0 | let @#=alternate | endif
  let &paste = old_paste
  call winrestview(view)
  return v:true
endfunction

function! s:ApplyAll(changes) abort
  for [uri, edits] in items(a:changes)
    for edit in edits
      call s:Apply(uri, edit)
    endfor
  endfor
endfunction

" Apply a `TextEdit` to the buffer at [uri].
function! s:Apply(uri, edit) abort
  let file_path = lsc#uri#documentPath(a:uri)
  if expand('%:p') !~# file_path
    execute 'edit' file_path
  endif
  if s:IsEmptyRange(a:edit.range)
    if a:edit.range.start.character >= len(getline(a:edit.range.start.line + 1))
      let insert = 'a'
    else
      let insert = 'i'
    endif
    let command = printf('%dG%d|%s%s',
        \ a:edit.range.start.line + 1,
        \ a:edit.range.start.character + 1,
        \ insert,
        \ a:edit.newText
        \)
  else
    " `back` handles end-exclusive range
    let back = 'h'
    if a:edit.range.end.character == 0
      let back = 'k$'
    endif
    let command = printf('%dG%d|v%dG%d|%sc%s',
        \ a:edit.range.start.line + 1,
        \ a:edit.range.start.character + 1,
        \ a:edit.range.end.line + 1,
        \ a:edit.range.end.character + 1,
        \ back,
        \ a:edit.newText
        \)
  endif
  execute 'normal!' command
  call lsc#file#onChange(file_path)
endfunction

function! s:IsEmptyRange(range) abort
  return a:range.start.line == a:range.end.line &&
      \ a:range.start.character == a:range.end.character
endfunction
