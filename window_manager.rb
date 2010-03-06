#!/usr/bin/ruby

require 'yaml'
require 'optparse'
require 'ostruct'
require 'osx/cocoa'
include OSX
OSX.require_framework 'ScriptingBridge'


class WindowManager

  class Window
    attr_reader :window
    attr_reader :name

    SIZE_FCC = 'ptsz'.unpack('N').first
    POSITION_FCC = 'posn'.unpack('N').first

    def initialize(window)
      @window = window
      @name = window.name.to_s
      @size_property = window.propertyWithCode(SIZE_FCC)
      @position_property = window.propertyWithCode(POSITION_FCC)
    end

    def size
      @size_property.get
    end

    def size=(size)
      @size_property.setTo(size)
    end

    def position
      @position_property.get
    end

    def position=(position)
      @position_property.setTo(position)
    end
  end


  class Process
    attr_reader :process
    attr_reader :windows

    def initialize(process)
      @process = process
      @windows = process.windows
    end

    # _title_ Window title regexp
    def find_window(title=nil)
      if title
        window = windows.find {|w| w.name.to_s =~ title }
        Window.new(window) if window
      else
        Window.new(windows.first)
      end
    end
  end


  def initialize
    @se = SBApplication.applicationWithBundleIdentifier_('com.apple.SystemEvents')
    @processes = @se.applicationProcesses
  end

  def refresh
    @processes = @se.applicationProcesses
  end

  # Find process with bundle ID _bundle_
  def find_process(bundle)
    process = @processes.find {|p| p.bundleIdentifier == bundle }
    Process.new(process) if process
  end

  # _settings_ Array of Hash, each Hash contains :process key which maps to bundle ID,
  # and zero or more window title Regexps (or nil) mapped to window setting Hashes.
  # Window setting hashes may contain :position array, :size array, 
  # [
  #   { :process => 'com.google.Chrome',
  #     /Gmail$/ => { :position => [300, 450] }
  #   }
  # ]
  def layout(settings)
    settings.each do |setting|
      setting = setting.dup
      process = find_process(setting.delete(:process))
      if process
        setting.each_pair do |title,ws|
          window = process.find_window(title)
          window.position = ws[:position] if ws[:position]
          window.size = ws[:size] if ws[:size]
        end
      end
    end
  end

  # Return current layout settings of all application windows
  def current_layout
    settings = []
    @processes.each do |p|
      next if p.windows.empty?
      setting = { :process => p.bundleIdentifier.to_s }
      p.windows.each do |w|
        w = Window.new(w)
        setting[Regexp.new(w.name)] = { :position => w.position.to_a.collect{|n|n.to_i},
                                        :size => w.size.to_a.collect{|n|n.to_i} }
      end
      settings << setting
    end
    settings
  end
end

def parse_opts(argv)
  options = OpenStruct.new
  options.layout = nil
  options.dumplayout = nil

  opts = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options] <layout.yaml>"
    opts.separator ""
    opts.separator "Input file is a yaml layout specification."
    opts.separator "Specific options:"

    opts.on("-d", "--dump",
            "Dump layout of all open windows") do |d|
      options.dumplayout = d
    end
    opts.on_tail("-h", "--help", "Show this message") do
      $stderr.puts opts
      exit(0)
    end
  end
  opts.parse!(argv)
  options.layout = argv.first
  if not options.dumplayout and not options.layout
    $stderr.puts(opts)
    exit(1)
  end

  options
end

if __FILE__ == $0
  options = parse_opts(ARGV)
  wm = WindowManager.new
  if options.dumplayout
    puts wm.current_layout.to_yaml
    exit(0)
  else
    wm.layout(YAML.load_file(options.layout))
  end
end