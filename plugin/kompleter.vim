" vim-kompleter - Smart keyword completion for Vim
" Maintainer:   Szymon Wrozynski
" Version:      0.0.9
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

if !exists('g:kompleter_fuzzy_search')
  let g:kompleter_fuzzy_search = 0
endif

" Set to 0 disable asynchronous mode (using forking).
if !exists('g:kompleter_async_mode')
  let g:kompleter_async_mode = 1
endif

" 0 - case insensitive
" 1 - case sensitive
" 2 - smart case sensitive (see :help 'smartcase')
if !exists('g:kompleter_case_sensitive')
  let g:kompleter_case_sensitive = 1
endif

au VimEnter * call s:startup()
au VimLeave * call s:cleanup()
au BufWritePre,BufRead,BufEnter * call s:process_keywords()

fun! s:process_keywords()
  let &completefunc = 'kompleter#Complete'
  let &l:completefunc = 'kompleter#Complete'
  ruby Kompleter.process_current_buffer
  ruby Kompleter.process_tagfiles
endfun

fun! s:cleanup()
  ruby Kompleter.cleanup
endfun

fun! s:startup()
  ruby Kompleter.startup
endfun

fun! kompleter#Complete(findstart, base)
  if a:findstart
    let line = getline('.')
    let start = col('.') - 1
    while start > 0 && line[start - 1] =~ '\w'
      let start -= 1
    endwhile
    return start
  else
    ruby VIM.command("return [#{Kompleter.complete(VIM.evaluate("a:base")).map { |c| "{ 'word': '#{c}', 'dup': 1 }" }.join(", ") }]")
  endif
endfun

ruby << EOF
require "thread"
require "drb/drb"

module Kompleter
  MIN_KEYWORD_SIZE = 3
  MAX_COMPLETIONS = 10
  DISTANCE_RANGE = 5000

  TAG_REGEX = /^([^\t\n\r]+)\t([^\t\n\r]+)\t.*?language:([^\t\n\r]+).*?$/
  KEYWORD_REGEX = /[_a-zA-Z]\w*/

  FUZZY_SEARCH = VIM.evaluate("g:kompleter_fuzzy_search")
  CASE_SENSITIVE = VIM.evaluate("g:kompleter_case_sensitive")
  ASYNC_MODE = VIM.evaluate("g:kompleter_async_mode") != 0

  module KeywordParser
    # TODO check if filenames are correctly recognized under Windows
    def self.parse_tags(filename)
      keywords = Hash.new(0)

      File.open(filename).each_line do |line|
        match = TAG_REGEX.match(line)
        keywords[match[1]] += 1 if match && match[1].length >= MIN_KEYWORD_SIZE
      end

      keywords
    end

    def self.parse_text(text)
      keywords = Hash.new(0)
      text.scan(KEYWORD_REGEX).each { |keyword| keywords[keyword] += 1 if keyword.length >= MIN_KEYWORD_SIZE }
      keywords
    end
  end

  class DataServer
    def initialize
      @data_id = 0
      @data = {}
      @data_mutex = Mutex.new
      @threads = {}
      @threads_mutex = Mutex.new
    end

    def add_text_async(text)
      data_id = next_data_id

      @threads[data_id] = Thread.new(text, data_id) do |t, did|
        keywords = KeywordParser.parse_text(t)
        @data_mutex.synchronize { @data[did] = keywords }
        @threads_mutex.synchronize { @threads.delete(did) }
      end

      data_id
    end

    def add_tags_async(filename)
      data_id = next_data_id

      @threads[data_id] = Thread.new(filename, data_id) do |fname, did|
        keywords = KeywordParser.parse_tags(fname)
        @data_mutex.synchronize { @data[did] = keywords }
        @threads_mutex.synchronize { @threads.delete(did) }
      end

      data_id
    end

    def get_data(data_id)
      return unless @data_mutex.try_lock
      data = @data.delete(data_id)
      @data_mutex.unlock
      data
    end

    def stop
      @threads_mutex.lock
      threads = @threads.dup
      @threads_mutex.unlock
      threads.each { |t| t.join }
      DRb.stop_service
    end

    private

    def next_data_id
      @data_id += 1
    end
  end

  class Repository
    attr_reader :repository

    def initialize
      @repository = {}
    end

    def lookup(query)
      candidates = Hash.new(0)

      repository.each do |key, keywords|
        if keywords.is_a?(Fixnum)
          keywords = Kompleter.data_server.get_data(keywords)
          next unless keywords
          repository[key] = keywords
        end
        words = query ? keywords.keys.find_all { |word| query =~ word } : keywords.keys
        words.each { |word| candidates[word] += keywords[word] }
      end

      candidates.keys.sort { |a, b| candidates[b] <=> candidates[a] }
    end

    def try_clean_unused(key)
      return true unless repository[key].is_a?(Fixnum)
      !Kompleter.data_server.get_data(repository[key]).nil?
    end
  end

  class BufferRepository < Repository
    def add(number, name, text)
      key = if name
        return unless try_clean_unused(number)
        repository.delete(number)
        name
      else
        number
      end

      return unless try_clean_unused(key)

      repository[key] = ASYNC_MODE ? Kompleter.data_server.add_text_async(text) : KeywordParser.parse_text(text)
    end
  end

  class TagsRepository < Repository
    def add(tags_file)
      return unless try_clean_unused(tags_file)
      repository[tags_file] = ASYNC_MODE ? Kompleter.data_server.add_tags_async(tags_file) : KeywordParser.parse_tags(tags_file)
    end
  end

  BUFFER_REPOSITORY = BufferRepository.new
  TAGS_REPOSITORY = TagsRepository.new
  TAGS_MTIMES = Hash.new(0)

  def self.process_current_buffer
    return if ASYNC_MODE && !$server_pid
    buffer = VIM::Buffer.current
    buffer_text = ""

    (1..buffer.count).each { |n| buffer_text << "#{buffer[n]}\n" }

    BUFFER_REPOSITORY.add(buffer.number, buffer.name, buffer_text)
  end

  def self.process_tagfiles
    return if ASYNC_MODE && !$server_pid
    tag_files = VIM.evaluate("tagfiles()")
    tag_files.each do |file|
      if File.exists?(file)
        mtime = File.mtime(file).to_i
        if TAGS_MTIMES[file] < mtime
          TAGS_MTIMES[file] = mtime
          TAGS_REPOSITORY.add(file)
        end
      end
    end
  end

  def self.cleanup
    if $server_pid
      data_server.stop
      Process.wait($server_pid)
      $server_pid = nil
    end
  end

  def self.startup
    if ASYNC_MODE
      port = data_server_port
      $server_pid = fork do
        DRb.start_service("druby://localhost:#{port}", DataServer.new)
        DRb.thread.join
        exit(0)
      end
      sleep 0.001 while $server_pid.nil?
    end
    process_tagfiles
  end

  def self.data_server
    @data_server ||= DRbObject.new_with_uri("druby://localhost:#{data_server_port}")
  end

  def self.data_server_port
    unless @data_server_port
      server = TCPServer.new("127.0.0.1", 0)
      @data_server_port = server.addr[1]
      server.close
    end
    @data_server_port
  end

  def self.complete(query)
    buffer = VIM::Buffer.current

    row, column = VIM::Window.current.cursor
    cursor = 0
    text = ""

    (1..buffer.count).each do |n|
      line = "#{buffer[n]}\n"
      text << line

      if row > n
        cursor += line.length
      elsif row == n
        cursor += column
      end
    end

    if cursor > DISTANCE_RANGE
      text = text[(cursor - DISTANCE_RANGE)..-1]
      cursor = DISTANCE_RANGE
    end

    if text.length > (cursor + DISTANCE_RANGE)
      text = text[0, cursor + DISTANCE_RANGE]
    end

    keywords = {}
    count = 0

    text.to_enum(:scan, KEYWORD_REGEX).each do |m|
      if m.length >= MIN_KEYWORD_SIZE
        if keywords[m]
          keywords[m] << $`.size
        else
          keywords[m] = [$`.size]
        end

        count += 1
      end
    end

    query = query.to_s # it could be a Fixnum if user is trying to complete a number, e.g. 10<C-x><C-u>

    if query.length > 0
      case_sensitive = (CASE_SENSITIVE == 2) ? (query =~ /[A-Z]/) : (CASE_SENSITIVE > 0)
      query = query.scan(/./).join(".*?") if FUZZY_SEARCH > 0
      query = case_sensitive ? /^#{query}/ : /^#{query}/i

      candidates_from_current_buffer = keywords.keys.find_all { |keyword| query =~ keyword }
    else
      query = nil
      candidates_from_current_buffer = keywords.keys
    end

    distances = {}

    candidates_from_current_buffer.each do |candidate|
      distance = keywords[candidate].map { |pos| (cursor - pos).abs }.min
      distance -= distance * (keywords[candidate].count / count.to_f)
      distances[candidate] = distance
    end

    candidates = candidates_from_current_buffer.sort { |a, b| distances[a] <=> distances[b] }

    if candidates.count >= MAX_COMPLETIONS
      return candidates[0, MAX_COMPLETIONS]
    else
      BUFFER_REPOSITORY.lookup(query).each do |buffer_candidate|
        candidates << buffer_candidate unless candidates.include?(buffer_candidate)
        return candidates if candidates.count == MAX_COMPLETIONS
      end

      TAGS_REPOSITORY.lookup(query).each do |tags_candidate|
        candidates << tags_candidate unless candidates.include?(tags_candidate)
        return candidates if candidates.count == MAX_COMPLETIONS
      end
    end

    candidates
  end
end
EOF
