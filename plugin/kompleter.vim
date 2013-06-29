" vim-kompleter - Smart keyword completion for Vim
" Maintainer:   Szymon Wrozynski
" Version:      0.0.8
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

" Set to empty string ("") to disable forking feature.
if !exists('g:kompleter_tmp_dir')
  let g:kompleter_tmp_dir = "/tmp"
endif

" 0 - case insensitive
" 1 - case sensitive
" 2 - smart case sensitive (see :help 'smartcase')
if !exists('g:kompleter_case_sensitive')
  let g:kompleter_case_sensitive = 1
endif

au BufWritePre,BufRead,BufEnter,VimEnter * call s:parse_keywords()
au VimLeave * call s:cleanup()

fun! s:parse_keywords()
  let &completefunc = 'kompleter#Complete'
  let &l:completefunc = 'kompleter#Complete'
  ruby Kompleter.parse_buffer
  ruby Kompleter.parse_tagfiles
endfun

fun! s:cleanup()
  ruby Kompleter.cleanup
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
module Kompleter
  MIN_KEYWORD_SIZE = 3
  MAX_COMPLETIONS = 10
  DISTANCE_RANGE = 5000
  PID = $$

  TAG_REGEX = /^([^\t\n\r]+)\t([^\t\n\r]+)\t.*?language:([^\t\n\r]+).*?$/
  KEYWORD_REGEX = /[_a-zA-Z]\w*/

  FUZZY_SEARCH = VIM.evaluate("g:kompleter_fuzzy_search")
  CASE_SENSITIVE = VIM.evaluate("g:kompleter_case_sensitive")
  TMP_DIR = VIM.evaluate("g:kompleter_tmp_dir")

  class Repository
    attr_reader :repository

    def initialize
      @repository = {}
    end

    def lookup(matcher)
      candidates = Hash.new(0)

      repository.each do |key, keywords|
        if keywords.is_a?(Fixnum)
          filename = File.join(TMP_DIR, "#{PID}_#{keywords}.vkd")
          next unless File.exists?(filename)
          keywords = File.open(filename, "rb") { |file| Marshal.load(file) }
          repository[key] = keywords
          File.delete(filename)
        end
        words = matcher ? keywords.keys.find_all { |word| matcher.call(word) } : keywords.keys
        words.each { |word| candidates[word] += keywords[word] }
      end

      candidates.keys.sort { |a, b| candidates[b] <=> candidates[a] }
    end

    def clean_all
      repository.keys.each { | key | try_clean_unused(key) }
    end

    def try_clean_unused(key)
      return true unless repository[key].is_a?(Fixnum)
      filename = File.join(TMP_DIR, "#{PID}_#{repository[key]}.vkd")
      exists = File.exists?(filename)
      File.delete(filename) if exists
      exists
    end
  end

  class BufferRepository < Repository
    def add(number, name, text)
      key = if name
        return unless try_clean_unused(number)
        repository[number] = {}
        name
      else
        number
      end

      return unless try_clean_unused(key)

      if TMP_DIR.empty?
        keywords = Hash.new(0)
        text.scan(KEYWORD_REGEX).each { |keyword| keywords[keyword] += 1 if keyword.length >= MIN_KEYWORD_SIZE }
        repository[key] = keywords
      else
        pid = fork do
          keywords = Hash.new(0)

          text.scan(KEYWORD_REGEX).each { |keyword| keywords[keyword] += 1 if keyword.length >= MIN_KEYWORD_SIZE }

          filename = File.join(TMP_DIR, "#{PID}_#{$$}.vkd")
          File.open(filename, "wb") { |f| f.write(Marshal.dump(keywords)) }
          exit!(0)
        end

        repository[key] = pid
      end
    end
  end

  class TagsRepository < Repository
    def add(tags_file)
      return unless try_clean_unused(tags_file)

      if TMP_DIR.empty?
        keywords = Hash.new(0)

        File.open(tags_file).each_line do |line|
          match = TAG_REGEX.match(line)
          keywords[match[1]] += 1 if match && match[1].length >= MIN_KEYWORD_SIZE
        end

        repository[tags_file] = keywords
      else
        pid = fork do
          keywords = Hash.new(0)

          File.open(tags_file).each_line do |line|
            match = TAG_REGEX.match(line)
            keywords[match[1]] += 1 if match && match[1].length >= MIN_KEYWORD_SIZE
          end

          filename = File.join(TMP_DIR, "#{PID}_#{$$}.vkd")
          File.open(filename, "wb") { |f| f.write(Marshal.dump(keywords)) }
          exit!(0)
        end

        repository[tags_file] = pid
      end
    end
  end

  BUFFER_REPOSITORY = BufferRepository.new
  TAGS_REPOSITORY = TagsRepository.new
  TAGS_MTIMES = Hash.new(0)

  def self.parse_buffer
    buffer = VIM::Buffer.current
    buffer_text = ""

    (1..buffer.count).each { |n| buffer_text << "#{buffer[n]}\n" }

    BUFFER_REPOSITORY.add(buffer.number, buffer.name, buffer_text)
  end

  def self.parse_tagfiles
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
    BUFFER_REPOSITORY.clean_all
    TAGS_REPOSITORY.clean_all
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
