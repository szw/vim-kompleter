require "drb/drb"

if RUBY_VERSION.to_f < 1.9
  require "iconv"

  class String
    def byte_length
      length
    end

    def try_repair_utf8
      ic = Iconv.new("UTF-8", "UTF-8//IGNORE")
      ic.iconv(self)
    rescue
      self
    end

    def chunks(size)
      chars.each_slice(size).map { |chars| chars.join }
    end
  end
else
  class String
    def byte_length
      bytes.to_a.count
    end

    def try_repair_utf8
      content = encode("UTF-16", "UTF-8", :invalid => :replace, :replace => "")
      content.encode("UTF-8", "UTF-16")
    rescue
      self
    end

    def chunks(size)
      scan(/.{1,#{size}}/m)
    end
  end
end

class String
  def try_repair_utf8!
    replace(try_repair_utf8)
  end
end

module Kompleter
  MIN_KEYWORD_SIZE   = 3
  MAX_COMPLETIONS    = 10
  DISTANCE_RANGE     = 5000
  MAX_CHUNK_SIZE     = 100_000

  TAG_REGEX          = /^([^\t\n\r]+)\t([^\t\n\r]+)\t.*?language:([^\t\n\r]+).*?$/u
  KEYWORD_REGEX      = (RUBY_VERSION.to_f < 1.9) ? /[\w]+/u : /[_[:alnum:]]+/u
  DASH_KEYWORD_REGEX = (RUBY_VERSION.to_f < 1.9) ? /[\-\w]+/u : /[\-_[:alnum:]]+/u

  CASE_SENSITIVE     = VIM.evaluate("g:kompleter_case_sensitive")
  ASYNC_MODE         = VIM.evaluate("g:kompleter_async_mode") != 0

  module KeywordParser
    def parse_tags(filename)
      keywords = Hash.new(0)

      File.open(Pathname.new(filename).realpath).each_line do |line|
        attepted_to_repair = false

        begin
          match = TAG_REGEX.match(line)
        rescue
          if attepted_to_repair
            next # repair was unsuccessfull (usually Iconv with Ruby 1.8.7), just skip this corrupted line
          else
            line.try_repair_utf8!
            attepted_to_repair = true
            retry
          end
        end

        keywords[match[1]] += 1 if match && match[1].length >= MIN_KEYWORD_SIZE
      end

      keywords
    end

    def parse_dict(filename)
      keywords = Hash.new(0)

      File.open(Pathname.new(filename).realpath).each_line do |line|
        line.chop!
        keywords[line] += 1 if line.length >= MIN_KEYWORD_SIZE
      end

      keywords
    end

    def parse_text(text, keyword_regex)
      keywords = Hash.new(0)
      text.scan(keyword_regex).each { |keyword| keywords[keyword] += 1 if keyword.length >= MIN_KEYWORD_SIZE }
      keywords
    end
  end

  class DataServer
    include KeywordParser

    def initialize
      @data_id       = 0
      @data          = {}
      @workers       = {}
      @data_mutex    = Mutex.new
      @workers_mutex = Mutex.new
      @chunks        = Hash.new { |hash, key| hash[key] = String.new }
    end

    def add_chunked_text(chunk, chunked_text_id = next_data_id)
      @chunks[chunked_text_id] << chunk
      chunked_text_id
    end

    def process_chunks_async(chunked_text_id, keyword_regex)
      text = @chunks.delete(chunked_text_id)
      add_text_async(text, keyword_regex)
    end

    def add_text_async(text, keyword_regex)
      new_work_async(:parse_text, [text, keyword_regex])
    end

    def add_tags_async(filename)
      new_work_async(:parse_tags, [filename])
    end

    def add_dict_async(filename)
      new_work_async(:parse_dict, [filename])
    end

    def get_data(data_id)
      @data_mutex.lock
      data = @data.delete(data_id)
      @data_mutex.unlock
      data
    end

    def expire_data_async(data_id)
      Thread.new(data_id) do |id|
        @workers_mutex.lock
        worker = @workers[id]
        @workers_mutex.unlock
        worker.join if worker
        get_data(id)
      end
    end

    def stop
      DRb.stop_service
    end

    def pid
      $$
    end

    private

    def new_work_async(parse_method, content)
      data_id = next_data_id

      Thread.new(parse_method, content, data_id) do |m, c, id|
        @workers_mutex.synchronize { @workers[id] = Thread.current }
        keywords = send(m, *c)
        @data_mutex.synchronize { @data[id] = keywords }
        @workers_mutex.synchronize { @workers.delete(id) }
      end

      data_id
    end

    def next_data_id
      @data_id += 1
    end
  end

  class Repository
    include KeywordParser

    attr_reader :repository

    def initialize(kompleter)
      @kompleter  = kompleter
      @repository = {}
    end

    def data_server
      @kompleter.data_server
    end

    def lookup(query, only_keys = nil)
      candidates = Hash.new(0)

      repository.each do |key, keywords|
        next if only_keys && !only_keys.include?(key)

        if keywords.is_a?(Fixnum)
          keywords = data_server.get_data(keywords)
          next unless keywords
          repository[key] = keywords
        end

        words = query ? keywords.keys.find_all { |word| query =~ word } : keywords.keys
        words.each { |word| candidates[word] += keywords[word] }
      end

      candidates.keys.sort { |a, b| candidates[b] <=> candidates[a] }
    end

    def expire_data(key)
      data_or_id = repository.delete(key)
      data_server.expire_data_async(data_or_id) if data_or_id && data_or_id.is_a?(Fixnum)
    end
  end

  class BufferRepository < Repository
    def add(number, keyword_regex, text)
      repository[number] = if ASYNC_MODE
        expire_data(number)
        if text.length > MAX_CHUNK_SIZE
          chunks          = text.chunks(MAX_CHUNK_SIZE)
          chunked_text_id = data_server.add_chunked_text(chunks[0])

          chunks[1, chunks.size].each { |chunk| data_server.add_chunked_text(chunk, chunked_text_id) }
          data_server.process_chunks_async(chunked_text_id, keyword_regex)
        else
          data_server.add_text_async(text, keyword_regex)
        end
      else
        parse_text(text, keyword_regex)
      end
    end
  end

  class TagsRepository < Repository
    def add(tags_file)
      repository[tags_file] = if ASYNC_MODE
        expire_data(tags_file)
        data_server.add_tags_async(tags_file)
      else
        parse_tags(tags_file)
      end
    end
  end

  class DictRepository < Repository
    def add(dict_file)
      repository[dict_file] = if ASYNC_MODE
        expire_data(dict_file)
        data_server.add_dict_async(dict_file)
      else
        parse_dict(dict_file)
      end
    end
  end

  class Kompleter
    attr_reader :buffer_repository, :buffer_ticks, :tags_repository, :dict_repository,
                :tags_mtimes, :data_server, :start_column, :real_start_column,
                :keyword_regex, :dictionaries

    def initialize
      @buffer_repository = BufferRepository.new(self)
      @buffer_ticks      = {}
      @tags_repository   = TagsRepository.new(self)
      @tags_mtimes       = Hash.new(0)
      @dict_repository   = DictRepository.new(self)
      @dictionaries      = []
    end

    def process_current_buffer
      buffer = VIM::Buffer.current
      tick   = VIM.evaluate("b:changedtick")

      return if buffer_ticks[buffer.number] == tick

      buffer_ticks[buffer.number] = tick
      buffer_text = ""

      (1..buffer.count).each { |n| buffer_text << "#{buffer[n]}\n" }

      buffer_repository.add(buffer.number, current_keyword_regex, buffer_text)
    end

    def expire_buffer(number)
      buffer_repository.expire_data(number) if ASYNC_MODE
      buffer_repository.repository.delete(number)
    end

    def process_tagfiles
      tag_files = VIM.evaluate("tagfiles()")

      tag_files.each do |file|
        if File.exists?(file)
          mtime = File.mtime(file).to_i
          if tags_mtimes[file] < mtime
            tags_mtimes[file] = mtime
            tags_repository.add(file)
          end
        end
      end
    end

    def process_dictionaries
      Dir.glob(VIM.evaluate("&dict")).each do |file|
        next if dictionaries.include?(file)
        dictionaries << file
        dict_repository.add(file)
      end
    end

    def process_all
      process_current_buffer
      process_tagfiles
      process_dictionaries
    end

    def stop_data_server
      return unless ASYNC_MODE
      pid = data_server.pid
      data_server.stop
      Process.wait(pid)
      DRb.stop_service
    rescue
    end

    def start_data_server
      return unless ASYNC_MODE
      DRb.start_service

      tcp_server = TCPServer.new("127.0.0.1", 0)
      port       = tcp_server.addr[1]

      tcp_server.close

      pid = fork do
        DRb.start_service("druby://localhost:#{port}", DataServer.new)
        DRb.thread.join
        exit(0)
      end

      @data_server = DRbObject.new_with_uri("druby://localhost:#{port}")

      tick = 0

      begin
        sleep 0.01
        @data_server.pid  # just to verify the connection
      rescue DRb::DRbConnError
        retry if (tick += 1) < 500

        Process.kill("KILL", pid)
        Process.wait(pid)

        ::Kompleter.send(:remove_const, :ASYNC_MODE)
        ::Kompleter.const_set(:ASYNC_MODE, false)

        msg = "Kompleter error: Cannot connect to the DRuby server at port #{port} in sensible time (over 5s). \n" \
              "Please restart Vim and try again. If the problem persists please open a new Github issue at \n" \
              "https://github.com/szw/vim-kompleter/issues. ASYNC MODE has been disabled for this session."

        VIM.command("echohl ErrorMsg")
        VIM.command("echo '#{msg}'")
        VIM.command("echohl None")
      end
    end

    def current_keyword_regex
      if VIM.evaluate("&isk").split(",").map { |filetype| filetype.strip }.include?("-") || VIM.evaluate("&lisp") == 1
        DASH_KEYWORD_REGEX
      else
        KEYWORD_REGEX
      end
    end

    def find_start_column
      @keyword_regex    = current_keyword_regex
      start_column      = VIM::Window.current.cursor[1]
      line              = VIM::Buffer.current.line.split(//u)
      counter           = 0
      real_start_column = 0

      line.each do |letter|
        break if counter >= start_column
        counter += letter.byte_length
        real_start_column += 1
      end

      while (start_column > 0) && (real_start_column > 0) && ((line[real_start_column - 1] =~ keyword_regex) == 0)
        real_start_column -= 1
        start_column -= line[real_start_column].byte_length
      end

      @real_start_column = real_start_column
      @start_column      = start_column
    end

    def complete(query)
      order      = VIM.evaluate("&complete").split(",")
      candidates = []

      # convert to string in case of Fixnum, e.g. after 10<C-x><C-u> and force UTF-8 for Ruby >= 1.9
      query = (RUBY_VERSION.to_f < 1.9) ? query.to_s : query.to_s.force_encoding("UTF-8")

      if query.length > 0
        case_sensitive = (CASE_SENSITIVE == 2) ? !(query =~ /[[:upper:]]+/u).nil? : (CASE_SENSITIVE > 0)
        query = case_sensitive ? /^#{query}/u : /^#{query}/ui
      else
        query = nil
      end

      order.each do |symbol|
        case symbol
        when "."
          break if complete_from_current(query, candidates)
        when "w"
          break if complete_from_windows(query, candidates)
        when "b"
          break if complete_from_buffers(query, candidates)
        when "t"
          break if complete_from_tags(query, candidates)
        when "k"
          break if complete_from_dictionaries(query, candidates)
        else
          next
        end
      end

      candidates
    end

    def complete_from_current(query, candidates)
      buffer = VIM::Buffer.current
      row    = VIM::Window.current.cursor[0]
      column = (RUBY_VERSION.to_f < 1.9) ? start_column : real_start_column

      cursor = 0
      text   = ""

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

      keywords = Hash.new { |hash, key| hash[key] = Array.new }
      count    = 0

      text.to_enum(:scan, keyword_regex).each do |m|
        if m.length >= MIN_KEYWORD_SIZE
          keywords[m] << $`.size
          count += 1
        end
      end

      candidates_from_current_buffer = query ? keywords.keys.find_all { |keyword| query =~ keyword } : keywords.keys
      distances = {}

      candidates_from_current_buffer.each do |candidate|
        distance = keywords[candidate].map { |pos| (cursor - pos).abs }.min
        distance -= distance * (keywords[candidate].count / count.to_f)
        distances[candidate] = distance
      end

      sorted_candidates = candidates_from_current_buffer.sort { |a, b| distances[a] <=> distances[b] }
      fill_candidates(sorted_candidates, candidates)
    end

    def fill_candidates(source, candidates)
      source.each do |candidate|
        candidates << candidate unless candidates.include?(candidate)
        return true if candidates.count >= MAX_COMPLETIONS
      end

      false
    end

    def complete_from_windows(query, candidates)
      current_tab_buffers = if VIM.evaluate("exists('g:f2_loaded') && g:f2_loaded") == 1
                              VIM.evaluate("keys(F2List(tabpagenr()))").map { |n| n.to_i }
                            else
                              VIM.evaluate("tabpagebuflist(tabpagenr())")
                            end

      current_tab_buffers.uniq!

      return true if fill_candidates(buffer_repository.lookup(query, current_tab_buffers), candidates)
      fill_candidates(buffer_repository.lookup(query, VIM.evaluate("s:all_visibles()").uniq - current_tab_buffers), candidates)
    end

    def complete_from_buffers(query, candidates)
      fill_candidates(buffer_repository.lookup(query), candidates)
    end

    def complete_from_tags(query, candidates)
      fill_candidates(tags_repository.lookup(query), candidates)
    end

    def complete_from_dictionaries(query, candidates)
      fill_candidates(dict_repository.lookup(query), candidates)
    end
  end
end

KOMPLETER = Kompleter::Kompleter.new
