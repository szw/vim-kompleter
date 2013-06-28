" vim-kompleter - Smart keyword completion for Vim
" Maintainer:   Szymon Wrozynski
" Version:      0.0.6
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

if !exists('g:kompleter_min_keyword_size')
  let g:kompleter_min_keyword_size = 3
endif

if !exists('g:kompleter_fuzzy_search')
  let g:kompleter_fuzzy_search = 0
endif

if !exists('g:kompleter_case_sensitive')
  let g:kompleter_case_sensitive = 2
endif

if !exists('g:kompleter_max_completions')
  let g:kompleter_max_completions = 10
endif

if !exists('g:kompleter_distance_range')
  let g:kompleter_distance_range = 5000
endif

augroup Kompleter
    au!
    au BufWritePre,BufRead,BufEnter,VimEnter * call s:parse_keywords()
augroup END

fun! s:parse_keywords()
  let &completefunc = 'kompleter#Complete'
  let &l:completefunc = 'kompleter#Complete'
  ruby Kompleter.parse_buffer
  ruby Kompleter.parse_tagfiles
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

module Kompleter
  MIN_KEYWORD_SIZE = VIM.evaluate("g:kompleter_min_keyword_size")
  FUZZY_SEARCH = VIM.evaluate("g:kompleter_fuzzy_search")
  MAX_COMPLETIONS = VIM.evaluate("g:kompleter_max_completions")
  CASE_SENSITIVE = VIM.evaluate("g:kompleter_case_sensitive")
  DISTANCE_RANGE = VIM.evaluate("g:kompleter_distance_range")
  TAG_REGEX = /^([^\t\n\r]+)\t([^\t\n\r]+)\t.*?language:([^\t\n\r]+).*?$/
  KEYWORD_REGEX = /[_a-zA-Z]\w*/

  class Repository
    attr_reader :repository, :repository_mutex

    def initialize
      @repository = {}
      @repository_mutex = Mutex.new
    end

    def lookup(matcher)
      return [] unless repository_mutex.try_lock
      repo = repository.dup
      repository_mutex.unlock

      candidates = Hash.new(0)

      repo.values.each do |keywords|
        words = matcher ? keywords.keys.find_all { |word| matcher.call(word) } : keywords.keys
        words.each { |word| candidates[word] += keywords[word] }
      end

      candidates.keys.sort { |a, b| candidates[b] <=> candidates[a] }
    end
  end

  class BufferRepository < Repository
    def add(number, name, text)
      keywords = Hash.new(0)
      text.scan(KEYWORD_REGEX).each { |keyword| keywords[keyword] += 1 if keyword.length >= MIN_KEYWORD_SIZE }

      repository_mutex.synchronize do
        key = if name
          repository[number] = {}
          name
        else
          number
        end

        repository[key] = keywords
      end
    end
  end

  class TagsRepository < Repository
    attr_reader :file_mtimes, :file_mtimes_mutex

    def initialize
      super
      @file_mtimes = {}
      @file_mtimes_mutex = Mutex.new
    end

    def add(tags_file)
      file_mtimes_mutex.synchronize do
        if File.exists?(tags_file)
          mtime = File.mtime(tags_file).to_i
          if !file_mtimes[tags_file] || file_mtimes[tags_file] < mtime
            file_mtimes[tags_file] = mtime
          else
            return
          end
        else
          return
        end
      end

      keywords = Hash.new(0)

      File.open(tags_file).each_line do |line|
        match = TAG_REGEX.match(line)
        keywords[match[1]] += 1 if match && match[1].length >= MIN_KEYWORD_SIZE
      end

      repository_mutex.synchronize { repository[tags_file] = keywords }
    end
  end

  TAGS_REPOSITORY = TagsRepository.new
  BUFFER_REPOSITORY = BufferRepository.new

  def self.parse_buffer
    buffer = VIM::Buffer.current
    buffer_text = ""

    (1..buffer.count).each { |n| buffer_text << "#{buffer[n]}\n" }

    Thread.new(buffer.number, buffer.name, buffer_text) { |number, name, text| BUFFER_REPOSITORY.add(number, name, text) }
  end

  def self.parse_tagfiles
    tag_files = VIM.evaluate("tagfiles()")
    tag_files.each do |file|
      Thread.new(file) { |f| TAGS_REPOSITORY.add(f) }
    end
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

      matcher = Proc.new { |keyword| query =~ keyword }
      candidates_from_current_buffer = keywords.keys.find_all { |keyword| matcher.call(keyword) }
    else
      matcher = nil
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
      BUFFER_REPOSITORY.lookup(matcher).each do |buffer_candidate|
        candidates << buffer_candidate unless candidates.include?(buffer_candidate)
        return candidates if candidates.count == MAX_COMPLETIONS
      end

      TAGS_REPOSITORY.lookup(matcher).each do |tags_candidate|
        candidates << tags_candidate unless candidates.include?(tags_candidate)
        return candidates if candidates.count == MAX_COMPLETIONS
      end
    end

    candidates
  end
end
EOF
