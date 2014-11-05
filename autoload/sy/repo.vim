" vim: et sw=2 sts=2

scriptencoding utf-8

" Init: values {{{1
let s:difftool = get(g:, 'signify_difftool', 'diff')

if executable(s:difftool)
  let s:vcs_dict = {
        \ 'git':      'git',
        \ 'hg':       'hg',
        \ 'svn':      'svn',
        \ 'darcs':    'darcs',
        \ 'bzr':      'bzr',
        \ 'fossil':   'fossil',
        \ 'cvs':      'cvs',
        \ 'rcs':      'rcsdiff',
        \ 'accurev':  'accurev',
        \ 'perforce': 'p4'
        \ }
else
  echomsg 'signify: No diff tool found -> no support for svn, darcs, bzr, fossil.'
  let s:vcs_dict = {
        \ 'git':      'git',
        \ 'hg':       'hg',
        \ 'cvs':      'cvs',
        \ 'rcs':      'rcsdiff',
        \ 'accurev':  'accurev',
        \ 'perforce': 'p4'
        \ }
endif

let s:vcs_list = get(g:, 'signify_vcs_list', [])
if empty(s:vcs_list)
  let s:vcs_list = keys(filter(s:vcs_dict, 'executable(v:val)'))
endif

let s:vcs_cmd = {
      \ 'git'     : 'git diff --no-color --no-ext-diff -U0',
      \ 'hg'      : 'hg diff --nodates -U0',
      \ 'svn'     : 'svn diff --diff-cmd '. s:difftool .' -x -U0',
      \ 'bzr'     : 'bzr diff --using '. s:difftool .' --diff-options=-U0',
      \ 'darcs'   : 'darcs diff --no-pause-for-gui --diff-command="'. s:difftool .' -U0 %1 %2"',
      \ 'fossil'  : 'fossil set diff-command "'. s:difftool .' -U 0" && fossil diff --unified -c 0',
      \ 'cvs'     : 'cvs diff -U0',
      \ 'rcs'     : 'rcsdiff -U0',
      \ 'accurev' : 'NOT IMPLEMENTED YET',
      \ 'perforce': 'p4 monitor show 2>&1 >/dev/null && env P4DIFF=diff p4 diff -dU0',
      \ }

if exists('g:signify_vcs_cmd')
  for vcs in g:signify_vcs_cmd
    let s:vcs_cmd[vcs] = g:signify_vcs_cmd[vcs]
  endfor
endif

" Function: #detect {{{1
function! sy#repo#detect() abort
  let dir = fnamemodify(b:sy.path, ':h')

  let vcs_list = s:vcs_list
  " Simple cache. If there is a registered VCS-controlled file in this
  " directory already, assume that this file is probably controlled by
  " the same VCS. Thus we shuffle that VCS to the top of our copy of
  " s:vcs_list, so we don't affect the preference order of s:vcs_list.
  if has_key(g:sy_cache, dir)
    let vcs_list = [g:sy_cache[dir]] + filter(copy(s:vcs_list), 'v:val != "'. g:sy_cache[dir] .'"')
  endif

  for type in vcs_list
    let [istype, diff] = sy#repo#get_diff_{type}()
    if istype
      return [ diff, type ]
    endif
  endfor

  return [ '', 'unknown' ]
endfunction

" Function: #get_diff_git {{{1
function! sy#repo#get_diff_git() abort
  let diff = sy#util#run_in_dir(
        \ fnamemodify(b:sy.path, ':h'),
        \ s:vcs_cmd.git .' -- '. sy#util#escape(fnamemodify(b:sy.path, ':t')))
  return v:shell_error ? [0, ''] : [1, diff]
endfunction

" Function: #get_stat_git {{{1
function! sy#repo#get_stat_git() abort
  let s:stats = []
  let root  = finddir('.git', fnamemodify(b:sy.path, ':h') .';')
  if empty(root)
    echohl ErrorMsg | echomsg 'Cannot find the git root directory: '. b:sy.path | echohl None
    return
  endif
  let root   = fnamemodify(root, ':h')
  let output = sy#util#run_in_dir(root, 'git diff --numstat')
  if v:shell_error
    echohl ErrorMsg | echomsg "'git diff --numstat' failed" | echohl None
    return
  endif
  for stat in split(output, '\n')
    let tokens = matchlist(stat, '\v([0-9-]+)\t([0-9-]+)\t(.*)')
    if empty(tokens)
      echohl ErrorMsg | echomsg 'Cannot parse this line: '. stat | echohl None
    elseif tokens[1] == '-'
      continue
    else
      let path = root . sy#util#separator() . tokens[3]
      if !bufexists(path)
        execute 'argadd '. path
      endif
      call add(s:stats, { 'bufnr': bufnr(path), 'text': tokens[1] .' additions, '. tokens[2] .' deletions', 'lnum': 1, 'col': 1 })
    endif
  endfor
  "call setqflist(stats)
endfunction

" Function: #get_diff_hg {{{1
function! sy#repo#get_diff_hg() abort
  let diff = system(s:vcs_cmd.hg .' -- '. sy#util#escape(b:sy.path))
  return v:shell_error ? [0, ''] : [1, diff]
endfunction

" Function: #get_diff_svn {{{1
function! sy#repo#get_diff_svn() abort
  let diff = system(s:vcs_cmd.svn .' -- '. sy#util#escape(b:sy.path))
  return v:shell_error ? [0, ''] : [1, diff]
endfunction

" Function: #get_diff_bzr {{{1
function! sy#repo#get_diff_bzr() abort
  let diff = system(s:vcs_cmd.bzr .' -- '. sy#util#escape(b:sy.path))
  return (v:shell_error =~ '[012]') ? [1, diff] : [0, '']
endfunction

" Function: #get_diff_darcs {{{1
function! sy#repo#get_diff_darcs() abort
  let diff = sy#util#run_in_dir(
        \ fnamemodify(b:sy.path, ':h'),
        \ s:vcs_cmd.darcs .' -- '. sy#util#escape(b:sy.path))
  return v:shell_error ? [0, ''] : [1, diff]
endfunction

" Function: #get_diff_fossil {{{1
function! sy#repo#get_diff_fossil() abort
  let diff = sy#util#run_in_dir(
        \ fnamemodify(b:sy.path, ':h'),
        \ s:vcs_cmd.fossil .' -- '. sy#util#escape(b:sy.path))
  return v:shell_error ? [0, ''] : [1, diff]
endfunction

" Function: #get_diff_cvs {{{1
function! sy#repo#get_diff_cvs() abort
  let diff = sy#util#run_in_dir(
        \ fnamemodify(b:sy.path, ':h'),
        \ s:vcs_cmd.cvs .' -- '. sy#util#escape(fnamemodify(b:sy.path, ':t')))
  return ((v:shell_error == 1) && (diff =~ '+++')) ? [1, diff] : [0, '']
endfunction

" Function: #get_diff_rcs {{{1
function! sy#repo#get_diff_rcs() abort
  let diff = system(s:vcs_cmd.rcs .' '. sy#util#escape(b:sy.path) .' 2>/dev/null')
  return v:shell_error ? [0, ''] : [1, diff]
endfunction

" Function: #get_diff_accurev {{{1
function! sy#repo#get_diff_accurev() abort
  let diff = sy#util#run_in_dir(
        \ fnamemodify(b:sy.path, ':h'),
        \ 'accurev diff '. sy#util#escape(fnamemodify(b:sy.path, ':t')) . ' -- -U0')
  return (v:shell_error != 1) ? [0, ''] : [1, diff]
endfunction

" Function: #get_diff_perforce {{{1
function! sy#repo#get_diff_perforce() abort
  let diff = system(s:vcs_cmd[perforce] .' '. sy#util#escape(b:sy.path))
  return v:shell_error ? [0, ''] : [1, diff]
endfunction

" Function: #get_stats {{{1
function! sy#repo#get_stats() abort
  if !exists('b:sy') || !has_key(b:sy, 'stats')
    return [-1, -1, -1]
  endif

  return b:sy.stats
endfunction
