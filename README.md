vim-kompleter
=============

A smart keyword completion plugin for Vim.

About
-----

This plugin requires a Vim with Ruby support compiled in. It provides fast, simple, smart, and
reliable keyword completion. It differs from the standard keyword completion by extensive use of
distance and frequency based algorithms for keyword matching. Those algorithms were inspired by
TextMate's keyword completion behavior.

Best results can be achived with the help of plugins like
[SuperTab](https://github.com/ervandew/supertab). In case of
[SuperTab](https://github.com/ervandew/supertab) all you have to do is to choose the user completion
function as the default one:

    let g:SuperTabDefaultCompletionType = "<c-x><c-u>"

Vim-Kompleter sets the user completion function to its own `kompleter#Complete`. Therefore it should
work also with plugins like [AutoComplPop](http://www.vim.org/scripts/script.php?script_id=1879),
though I didn't test that yet.


Installation
------------

In case of Pathogen, just clone the repo to your `bundles` directory:

    git clone https://github.com/szw/vim-kompleter.git

If you prefer Vundle, add the following snippet to your `.vimrc` file:

    Bundle "szw/vim-kompleter"

Vim-Kompleter requires Ruby bindings to be present in your Vim. It has been tested with Ruby 1.8.7
and 2.0.0 (both on Mac OSX) and seems working pretty well. I believe it will work with other
configurations seamlessly too. In case of any problems create an issue please.


Forking
-------

Kompleter by default uses the "fork" feature to perform asynchronous tasks, which is unavailable
on Windows or NetBSD4. In that case, or if you just want to disable asynchronous mode please set the
following variable to `0` (by default it is `1`):

    let g:kompleter_async_mode = 0

If asynchronous mode is disabled, the plugin may sometimes work less smoothly, however it depends
heavily on the user system configuration and the concrete project. For example, without async mode
it took a 1-2 seconds to parse a large tags file on Vim startup and it was a noticeable lag.


#### Technical Note ####

Early versions of Vim-Kompleter were using plain threads but it wasn't a stable solution. Sometimes
in Vim Ruby threads just die unexpectedly and that leads to hard to catch failures or malfunctions.
Perhaps a Python implementation could handle threading a bit better (but it wouldn't work on ARM
processors anyway).

Right now Vim-Kompleter forks a process with a DRuby server which performs asynchronous tasks (parsing
keywords). It actually seems pretty stable and very fast.


Case-Sensitive Completion
-------------------------

Vim-Kompleter provides three modes of case-sensitive completion:

* case-sensitive (`1` - default one)

* case-insensitive (`0`)

* smartcase (`2`)

  In case you miss so-called _smartcase_ completion known from standard Vim completion algorithm.
  See `:help 'smartcase'` for more info.

Smartcase is often used in Vim because it's handy while searching or substitute things. The same
search engine settings are used for the standard Vim keyword completion algorithm. In this way
you cannot just limit the `smartcase` option only to searching/substituting as command facility.
It will also _enhance_ Vim's keyword matching and that is really frustrating. But if you used to
work with smartcase, it's okay. You can enable it in Vim-Kompleter too:

    let g:kompleter_case_sensitive = 2

By default, the plain case sensitive completion is set (`let g:kompleter_case_sensitive = 1`).


Fuzzy Search
------------

It looks like it's the next "must have" nowadays. However, chances are you won't like it very much,
because standard matching will provide you highly accurate results. But again, it strongly depends
on your projects and your writing/coding habits as well. Fuzzy search (turned off by default) can be
enabled like below:

    let g:kompleter_fuzzy_search = 1


Unicode Support
---------------

Vim-Kompleter works with multibyte strings (even with Ruby 1.8.7). It can parse and complete
keywords with Unicode characters, like _żaba_ (a frog in Polish) or _Gdańsk_ (a city name). If you
have Vim compiled with Ruby 1.9 or greater it should even differentiate correctly upper and lower
case characters. For example if you complete _ż_ you get candidates like _żaba_ but not _Żory_
(another city). Ruby 1.8.7 is a bit dumb here, but anyways Unicode works quite nice, isn't it? :)


Self-Promotion
--------------

If you like the plugin, don't hesitate to add a star. This way I can estimate plugin's popularity
and plan its future development. If something's broken or you've just found a bug, please fill the
Github issue. You can also consult pull requests that way and ask about new features.


Author and License
------------------

Copyright (c) 2013 Szymon Wrozynski and Contributors. Licensed under a the same license as Vim
itself. See `:help license` for more details.

Thanks to [Valloric](https://github.com/Valloric) and
[YouCompleteMe](https://github.com/Valloric/YouCompleteMe) community for inspiration.

Also thanks to [Gotar](https://github.com/gotar) for bugs catching :).
