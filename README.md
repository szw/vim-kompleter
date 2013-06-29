vim-kompleter
=============

A smart keyword completion plugin for Vim.

About
-----

This plugin requires a Vim with Ruby support compiled in. It provides fast, simple, smart and
reliable keyword completion. It differs from the standard keyword completion by extensive use of
distance and frequency based algorithms while matching identifiers. The algorithms was inspired by
TextMate's keyword completion behavior.

Best results can be achived with the help of plugins like SuperTab. In case of SuperTab all you have
to do is to choose the user completion function as the default one:

    let g:SuperTabDefaultCompletionType = "<c-x><c-u>"


Forking
-------

Kompleter by default uses the "fork" feature which seems unavailable on Windows or NetBSD4. In that
case, or if you just want to disable forking set the temporary directory to empty string:

    let g:kompleter_tmp_dir = ""

Otherwise make sure it points to a valid and sensible place (by default it points to `/tmp`). This
is important because forking needs to store some temporary files while working.

If forking is disabled, the plugin may sometimes work less smoothly, however it depends heavily on
the user configuration and the concrete project settings. For example, without forking it took a 1-2
seconds to parse a large tags file on Vim startup and it was a noticeable lag.

Early versions of Vim-Kompleter were using threads but it was an unstable solution. Sometimes Ruby
threads are just dying unexpectedly in Vim causing hard to catch failures or malfunctions. Perhaps
a Python implementation could handle threading a bit better.

Anyway, forking seems pretty stable and fast enough.


Case-Sensitive Completion
-------------------------

Vim-Kompleter provides three modes of case-sensitive completion:

* case-sensitive (`1` - default one)
* case-insensitive (`0`)
* smartcase (`2`) - it's often used in Vim, probably because it's handy in searching, and you cannot
  just disable it in the standard Vim completion engine. In the case you miss that feature you can
  turn it on. See `:help 'smartcase'` for more info.

To set case-sensitive option use:

    let g:kompleter_case_sensitive = 1


Fuzzy Search
------------

It looks like it's the next "must have" nowadays. However, chances are you will not like it very
much here, because you will find result less accurate. But again, it seems to depend strongly on
your projects and your writing/coding habits as well. Fuzzy search is turned off by default:

    let g:kompleter_fuzzy_search = 0


Self-Promotion
--------------

If you like the plugin, don't hesitate to add a star. This way I can estimate plugin's popularity
and plan its future development. If something's broken or you've just found a bug, please fill the
issue. You can also consult pull requests that way and ask about new features.


Author and License
------------------

Copyright (c) 2013 Szymon Wrozynski and Contributors. Licensed under a Vim-like license.

Thanks to Val Markovic and YouCompleteMe (both plugin and community) for inspiration.
