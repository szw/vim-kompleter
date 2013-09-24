Vim-Kompleter
=============

A smart, fast, simple, and reliable keyword completion replacement for Vim.

It differs from the standard keyword completion by extensive usage of distance and frequency
algorithms in order to perform keyword matching. Those algorithms are inspired by TextMate's keyword
completion experiences.

It is written with _K_ to emphasize its new approach to _keyword_ completion.


About
-----

The keyword completion is a standard Vim feature available with `<C-n>` or `<C-p>` key bindings.
`<C-n>` typically shows the completion window with identifiers parsed from the cursor till the end
of the file, combined with keywords from other sources (buffers, ctags, and so on). `<C-p>`
\- similarly - shows keywords from the cursor up to the very beginning of the file.

So, why the replacement? Vim-Kompleter also shows you keyword completions but in a somewhat
different way.

First, it doesn't differentiate those two modes (before and after the cursor). Just `<C-x><C-u>` 
is enough - it's a standard trigger for the so-called user completion function. By default,
Vim-Kompleter replaces standard keyword completion triggers (`<C-n>` and `<C-p>`) with proper
`<C-x><C-u>` calls. Otherwise, with the help of plugins like
[SuperTab](https://github.com/ervandew/supertab) you can use just `<Tab>`, `<S-Tab>` key
combinations.

On each key press of the given combination, the plugin computes distances between cursor and
keywords in the current file. Then it combines the results with a keyword frequency factor. 
Next, it adds some most relevant keywords from buffers, ctags, or dictionaries 
(the frequency is considered too).

Finally, the completion list is always keep short (max 10 items) and focused on most accurate
results. The plugin also preserves the standard Vim completion order of completion sources.


Installation
------------

In case of Pathogen, just clone the repo to your `bundles` directory:

    git clone https://github.com/szw/vim-kompleter.git

If you prefer Vundle, add the following snippet to your `.vimrc` file and perform `:BundleInstall`:

    Bundle "szw/vim-kompleter"

**In both cases you should restart Vim.**

Vim-Kompleter **requires** Ruby bindings to be compiled in your Vim. It has been tested with Ruby
1.8.7 and 2.0.0 (both on Mac OSX) and seems working pretty well. And I believe it will work with
other configurations seamlessly too. In case of any problems please create an issue.

By default, Vim-Kompleter replaces default keyword completion triggers (`<C-n>`, `<C-p>`). If you
want to keep original Vim keyword completion mappings set `g:kompleter_replace_standard_mappings` to
0:

    let g:kompleter_replace_standard_mappings = 0

On the other hand, you might try plugins like [SuperTab](https://github.com/ervandew/supertab). In
such case all you have to do is to make sure the user completion function is the default one:

    let g:SuperTabDefaultCompletionType = "<c-x><c-u>"

Of course, you can do it in many ways. You can combine the _user completion_ with omni-completion
and so on. See SuperTab documentation for details [`:help
supertab`](https://github.com/ervandew/supertab/blob/master/doc/supertab.txt)

Vim-Kompleter sets the user completion function to its own `kompleter#Complete`. Therefore it should
work also with plugins like [AutoComplPop](http://www.vim.org/scripts/script.php?script_id=1879),
though I didn't test that yet.


Forking
-------

Kompleter by default uses the "fork" feature to perform asynchronous tasks. It's cool but seems
unavailable on Windows or NetBSD4. In that case, or if you just want to disable asynchronous mode
please set the following variable to `0` (by default it is `1`):

    let g:kompleter_async_mode = 0

If asynchronous mode is disabled, the plugin may sometimes work less smoothly, however it depends
heavily on the user system configuration and the current project. For example, without async mode it
took about 1 - 2 seconds to parse a 30 MB tags file on Vim startup and it was a noticeable lag.


#### Technical Note ####

Early versions of Vim-Kompleter were using plain threads but that wasn't a stable solution.
Sometimes in Vim Ruby threads just die unexpectedly and that leads to hard to catch failures or
malfunctions. Perhaps a Python implementation could handle threading a bit better (but it wouldn't
work on ARM processors anyway).

Right now Vim-Kompleter forks a process with a DRuby server which performs asynchronous tasks
(parsing keywords). Currently, this solution seems to be pretty stable and very fast. The best
results can be achieved if you compile your Vim with decent Ruby bindings (>= 2.0).


Case-Sensitive Completion
-------------------------

Vim-Kompleter provides three modes of case-sensitive completion:

* case-sensitive (`1` - default one)

* case-insensitive (`0`)

* smartcase (`2`)

  In case you are looking for the _smartcase_ completion known from standard Vim completion algorithm.
  See `:help 'smartcase'` for more info.

Smartcase is often used in Vim because it's handy while searching or substitute things.
Unfortunately, the same search engine settings are used for the standard Vim keyword completion
algorithm. Therefore you cannot just limit the `smartcase` option only to searching/substituting.
Smartcase will also _enhance_ Vim's keyword matching and it's really annoying.

By default Kompleter saves you, at least partially, from that headache by using its custom
case-sensitive settings together with sensible defaults. But if you used to work with
smartcase while keyword completing, it's okay. You can enable the same in Vim-Kompleter too:

    let g:kompleter_case_sensitive = 2

As said before, by default, the plain case sensitive keyword matching is set (not the smartcase):

    let g:kompleter_case_sensitive = 1


Unicode Support
---------------

Vim-Kompleter works with multibyte strings (even with Ruby 1.8.7). It can parse and complete
keywords with Unicode characters, like _żaba_ (a frog in Polish) or _Gdańsk_ (a city name). If you
have Vim compiled with Ruby 1.9 or greater it should even differentiate correct upper and lower case
characters. For example if you complete _ż_ you will get candidates like _żaba_ but not _Żory_
(another city). Ruby 1.8.7 is a bit dumb with this unfortunately. 

Anyways, Unicode works on both versions and that's quite nice, isn't it? :)


Lispy Identifiers
-----------------

Lispy identifiers are just keywords with a hyphen inside allowed. Such keywords are common not only
in Lisp family but also in a bunch of web interface languages, like HTML or CSS. Normally, in Vim,
you can enable them by adjusting the `:set iskeyword` option to contain the dash character `-` or
by setting the _lisp_ option (`:set lisp`). Vim-Kompleter will recognize that and allows the dash in
identifiers too.

You can provide the Lispy identifiers for certain filetypes permanently in your `.vimrc` by adding
a dash to the `isk` option like in the example below:

    " Lispy identifiers support
    au FileType lisp,clojure,html,xml,xhtml,haml,eruby,css,scss,sass,javascript,coffee setlocal isk+=-

See `:help iskeyword` or `:help isk` to find out how Vim recognizes keywords in various commands like
`*` or `#`. Moreover, see `:help lisp` for more details of the Lisp support in Vim.


Completions order
-----------------

Kompleter follows the precedence of completion sources defined in the `'complete'` settings. It
understands: `'.'` (the current file), `'w'` (open windows and [F2's](https://github.com/szw/vim-f2)
current tab buffers), `'b'` (all loaded buffers), `'t'` (tags), and `'k'` (dictionaries). 

Vim-Kompleter can handle custom dictionary completions. You can specify them with the Vim
`'dictionary'` option. Then, if you add the dictionary completion to be included in the keyword
completion (via `:set complete += k`) Kompleter will add words from dictionaries. See 
`:help 'dictionary'` and `:help 'complete'` for more information.


Self-Promotion
--------------

If you like the plugin, don't hesitate to add a star. This way I can estimate plugin's popularity
and plan its future development. If something's broken or you've just found a bug, please add a new
Github issue. You can also consult pull requests and ask about new features that way.


Author and License
------------------

Copyright (c) 2013 Szymon Wrozynski and Contributors. Licensed under a the same license as Vim
itself. See `:help license` for more details.

Thanks to [Valloric](https://github.com/Valloric) and
[YouCompleteMe](https://github.com/Valloric/YouCompleteMe) community for inspiration.

Also big thanks to [Gotar](https://github.com/gotar) for excelent bugs spotting :).
