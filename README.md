vim-kompleter
=============

A smart keyword completion plugin for Vim.

About
-----

This plugin requires a Vim with Ruby support compiled in. It provides fast, simple, smart and
reliable keyword completion. It differs from the standard keyword completion by extensive use of
distance and frequency based algorithms while matching identifiers. Those algorithms are inspired by
TextMate's keyword completion behavior.

Best results can be achived with the help of plugins like SuperTab. In case of SuperTab all you have
to do is to choose the user completion function as the default one:

    let g:SuperTabDefaultCompletionType = "<c-x><c-u>"

Vim-Kompleter sets the user completion function to its own `kompleter#Complete`.


Forking
-------

Kompleter by default uses the "fork" feature to perform asynchronous tasks, which seems unavailable
on Windows or NetBSD4. In that case, or if you just want to disable asynchronous mode set the
following variable to `0` (by default it is `1`):

    let g:kompleter_async_mode = 0

If asynchronous mode is disabled, the plugin may sometimes work less smoothly, however it depends
heavily on the user configuration and the concrete project settings. For example, without async mode
it took a 1-2 seconds to parse a large tags file on Vim startup and it was a noticeable lag.


#### Technical note ####

Early versions of Vim-Kompleter were using plain threads but it wasn't a stable solution. Sometimes
in Vim Ruby threads just die unexpectedly and that leads to hard to catch failures or malfunctions.
Perhaps a Python implementation could handle threading a bit better (but it wouldn't work on ARM
processors anyway).

Right now Vim-Kompleter forks a process with DRuby server which performs asynchronous tasks (parsing
identifiers). It seems pretty stable and fast enough.


Case-Sensitive Completion
-------------------------

Vim-Kompleter provides three modes of case-sensitive completion:

* case-sensitive (`1` - default one)
* case-insensitive (`0`)
* smartcase (`2`) - if you miss smarcase completion known from standard Vim completion algorithm.
  See `:help 'smartcase'` for more info.

Smartcase is often used in Vim, probably because it's handy in searching and the same search engine
settings are used for standard Vim keyword completion algorithm. In other words, you cannot just use
`smartcase` as a defalut for search/replace commands and not for Vim keyword completion. In
Vim-Kompleter this is not the case. You can choose whatever you want.

For example, to set case-sensitive option use:

    let g:kompleter_case_sensitive = 1


Fuzzy Search
------------

It looks like it's the next "must have" nowadays. However, chances are you won't like it very much,
because standard matching will provide you very accurate results. But again, it strongly depends on
your projects and your writing/coding habits as well. Fuzzy search is turned off by default:

    let g:kompleter_fuzzy_search = 0


Self-Promotion
--------------

If you like the plugin, don't hesitate to add a star. This way I can estimate plugin's popularity
and plan its future development. If something's broken or you've just found a bug, please fill the
Github issue. You can also consult pull requests that way and ask about new features.


Author and License
------------------

Copyright (c) 2013 Szymon Wrozynski and Contributors. Licensed under a Vim-like license.

Thanks to Val Markovic and YouCompleteMe (both plugin and community) for inspiration.
