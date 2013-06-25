" vim-kompleter - Smart idenfifier completion for Vim
" Maintainer:   Szymon Wrozynski
" Version:      0.0.3
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

if !exists('g:kompleter_min_token_size')
  let g:kompleter_min_token_size = 3
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

augroup Kompleter
    au!
    au BufRead,BufEnter,VimEnter * call s:parse_indetifiers()
augroup END

fun! s:parse_indetifiers()
  let &completefunc = 'kompleter#Complete'
  let &l:completefunc = 'kompleter#Complete'
  ruby Kompleter.add_current_buffer
  ruby Kompleter.add_tagfiles
endfun

fun! kompleter#Complete(findstart, base)
  if a:findstart
    let line = getline('.')
    let start = col('.') - 1
    while start > 0 && line[start - 1] =~ '[_a-zA-Z]'
      let start -= 1
    endwhile
    return start
  else
    ruby VIM::command("return [#{Kompleter.complete(VIM::evaluate("a:base")).map { |c| "{ 'word': '#{c}', 'dup': 1 }" }.join(", ") }]")
  endif
endfun

ruby << EOF
require "thread"

module Kompleter
  MIN_TOKEN_SIZE = VIM::evaluate("g:kompleter_min_token_size")
  FUZZY_SEARCH = VIM::evaluate("g:kompleter_fuzzy_search")
  MAX_COMPLETIONS = VIM::evaluate("g:kompleter_max_completions")
  CASE_SENSITIVE = VIM::evaluate("g:kompleter_case_sensitive")

  class Tokenizer
    TOKEN_REGEX = /[_a-zA-Z]\w*/

    attr_reader :text

    def initialize(text)
      @text = text
      @count = 0
    end

    def tokens
      @tokens ||= parse_tokens
    end

    def count
      tokens
      @count
    end

    private

    def parse_tokens
      tokens = {}

      text.to_enum(:scan, TOKEN_REGEX).each do |m|
        if m.length >= MIN_TOKEN_SIZE
          if tokens[m]
            tokens[m] << $`.size
          else
            tokens[m] = [$`.size]
          end

          @count += 1
        end
      end

      tokens
    end
  end

  module BufferRepository
    @repository = {}
    @repository_mutex = Mutex.new

    def self.add(buffer_name, tokens)
      @repository_mutex.synchronize do
        @repository[buffer_name] = {}
        tokens.each { |token, positions| @repository[buffer_name][token] = positions.size }
      end
    end

    def self.lookup(matcher)
      candidates = {}
      repo = nil
      @repository_mutex.synchronize { repo = @repository.dup }
      repo.each do |_, tokens|
        words = matcher ? tokens.keys.find_all { |word| matcher.call(word) } : tokens.keys
        words.each do |word|
          if candidates[word]
            candidates[word] += tokens[word]
          else
            candidates[word] = tokens[word]
          end
        end
      end
      candidates.keys.sort { |a, b| candidates[b] <=> candidates[a] }
    end
  end

  module TagsRepository
    TAG_REGEX = /^([^\t\n\r]+)\t([^\t\n\r]+)\t.*?language:([^\t\n\r]+).*?$/

    @repository = {}
    @repository_mutex = Mutex.new

    @file_mtimes = {}
    @file_mtimes_mutex = Mutex.new

    def self.add(tags_file)
      @file_mtimes_mutex.synchronize do
        if File.exists?(tags_file)
          mtime = File.mtime(tags_file).to_i
          if !@file_mtimes[tags_file] || @file_mtimes[tags_file] < mtime
            @file_mtimes[tags_file] = mtime
          else
            return
          end
        else
          return
        end
      end

      File.open(tags_file).each_line do |line|
        match = TAG_REGEX.match(line)
        if match && match[1].length >= MIN_TOKEN_SIZE
          @repository_mutex.synchronize do
            if @repository[match[1]]
              @repository[match[1]] += 1
            else
              @repository[match[1]] = 1
            end
          end
        end
      end
    end

    def self.lookup(matcher)
      repo = nil
      @repository_mutex.synchronize { repo = @repository.dup }
      candidates = {}
      words = matcher ? repo.keys.find_all { |token| matcher.call(token) } : repo.keys
      words.each do |word|
        if candidates[word]
          candidates[word] += repo[word]
        else
          candidates[word] = repo[word]
        end
      end
      candidates.keys.sort { |a, b| candidates[b] <=> candidates[a] }
    end
  end

  def self.current_buffer_name
    VIM::Buffer.current.name
  end

  def self.current_buffer_text_and_position
    buffer = VIM::Buffer.current

    row, col = VIM::Window.current.cursor
    cursor_in_text = 0
    text = ""

    (1...buffer.count).each do |n|
      line = buffer[n]
      text << line + "\n"

      if row > n
        cursor_in_text += line.length + 1
      elsif row == n
        cursor_in_text += col
      end
    end

    [text, cursor_in_text]
  end

  def self.add_current_buffer
    text, _ = current_buffer_text_and_position
    Thread.new { BufferRepository.add(current_buffer_name, Tokenizer.new(text).tokens) }
  end

  def self.add_tagfiles
    tag_files = VIM.evaluate("tagfiles()")
    tag_files.each do |file|
      Thread.new { TagsRepository.add(file) }
    end
  end

  def self.complete(query)
    current_text, cursor = current_buffer_text_and_position
    current_tokenizer = Tokenizer.new(current_text)

    if query.length > 0
      case_sensitive = (CASE_SENSITIVE == 2) ? (query =~ /[A-Z]/) : (CASE_SENSITIVE > 0)
      query = query.scan(/./).join(".*?") if FUZZY_SEARCH > 0
      query = case_sensitive ? /^#{query}/ : /^#{query}/i

      matcher = Proc.new { |token| query =~ token }
      candidates_from_current_buffer = current_tokenizer.tokens.keys.find_all { |token| matcher.call(token) }
    else
      matcher = nil
      candidates_from_current_buffer = current_tokenizer.tokens.keys
    end

    distances = {}

    candidates_from_current_buffer.each do |candidate|
      distance = current_tokenizer.tokens[candidate].map { |pos| (cursor - pos).abs }.min
      count_factor = current_tokenizer.tokens[candidate].count / current_tokenizer.count.to_f
      distance -= distance * count_factor
      distances[candidate] = distance
    end

    candidates = candidates_from_current_buffer.sort { |a, b| distances[a] <=> distances[b] }

    if candidates.count >= MAX_COMPLETIONS
      return candidates[0, MAX_COMPLETIONS]
    else
      BufferRepository.lookup(matcher).each do |buffer_candidate|
        candidates << buffer_candidate unless candidates.include?(buffer_candidate)
        return candidates if candidates.count == MAX_COMPLETIONS
      end

      TagsRepository.lookup(matcher).each do |tags_candidate|
        candidates << tags_candidate unless candidates.include?(tags_candidate)
        return candidates if candidates.count == MAX_COMPLETIONS
      end
    end

    candidates
  end
end
EOF
