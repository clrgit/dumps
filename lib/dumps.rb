# frozen_string_literal: true

require_relative "dumps/version"

require 'indented_io'
require 'constrain'
include Constrain

module Dumps
  def self.dp(object) = $stderr.puts object.inspect
  def self.dputs(object = "") = $stderr.puts object

  # Enable/disable time zone in timestamps. Default is disabled
  def self.timezone=(b)
    constrain b, TrueClass, FalseClass
    @@timezone = b
  end

  # Returns the current time
  def self.timezone? = @@timezone

  # The eponymic method of the Dumps module. It is actually just a method for
  # the lazy developer in the tcase where dumps should be seperated by a blank
  # line to enhance readability
  def self.dumps(...) dump(...); puts end

  # :call-seq:
  #   dump(object, label|ident|index|range..., new: false, exclude: nil)
  #
  # ::dump also supports an :index option but it is only meant to be used
  # internally
  #
  def self.dump(object, *args, **opts)
    constrain args, [String, Symbol, Integer, Range, nil]
    constrain object.is_a?(Dumps) || opts.slice(:new, :exclude).empty?, true
    label = args.select { |arg| arg.nil? || arg.is_a?(String) }.last
    idents = args.select { |arg| arg.is_a?(Symbol) }
    indexes = args.select { |arg| arg.is_a?(Integer) || arg.is_a?(Range) }
    idents.empty? || indexes.empty? or raise ArgumentError, "Symbols and Integers can't be combined"
    
    # Register if this is an anonymous top-level call to ::dump (ie. the first
    # #dump method to be called from the application)
    self.anonymous = label.nil? if empty?

    case object
      when Array; dump_array(object, label, *indexes)
      when Hash; dump_hash(object, label, *idents)
      when Dumps; dump_object(object, label, *idents, **opts)
    else
      idents.empty? or raise ArgumentError
      Dumps.dump_label(label, false); dump_value(object)
    end
  end

  def self.dump_label(label, newline = true)
    constrain label, String, nil
    print "#{label}:#{newline ? "\n" : " "}" if label
  end

  def self.dump_array(array, label, *indexes, **opts)
    constrain array, Array
    constrain indexes, [Integer, Range]
    indexes = 
        if indexes.empty?
          array.each_index
        else
          indexes.map { |e|
            e.is_a?(Range) ? e.each.to_a : e
          }.flatten
        end
    context(array, label, **opts) {
      dump_label(label)
      level = label ? 1 : 0
      indent(level) { 
        indexes.each { |i| print "- "; indent(bol: false) { dump(array[i], index: i) } }
      }
    }
  end

  def self.dump_hash(hash, label, *idents, **opts)
    constrain hash, Hash
    constrain idents, [Symbol]
    keys = idents.empty? ? hash.keys : idents
    context(hash, label, **opts) {
      dump_label(label)
      level = label ? 1 : 0
      indent(level) { 
        keys.each { |key| dump(hash[key], key.to_s) }
      }
    }
  end

  def self.dump_object(object, label, *idents, new: false, exclude: nil, **opts)
    constrain object, Dumps
    constrain label, String, nil
    constrain idents, [Symbol]
    constrain new, false, true
    constrain exclude, nil, [Symbol]
    idents = (new ? [] : object.class.dump_identifiers) \
           + idents \
           - (exclude.nil? ? [] : exclude)
    idents.uniq!
    if idents.empty?
      context(object, label, **opts) { dump_label(label, false); dump_id(object) }
    else
      context(object, label, **opts) {
        dump_label(label)
        level = label ? 1 : 0
        indent(level) {
          idents.each { |ident|
            attr_method = :"dump_attr_#{ident}"
            value_method = :"dump_value_#{ident}"

            if overrides?(object, attr_method)
              object.send(attr_method)
            elsif overrides?(object, :dump_attr)
              object.send(:dump_attr, ident)
            elsif overrides?(object, value_method)
              value = capture { object.send(value_method) }
              newline = value =~ /\n./
              dump_label(ident.to_s, newline)
              print value
            elsif overrides?(object, :dump_value)
              value = capture { object.send(:dump_value, ident) }
              newline = value =~ /\n./
              dump_label(ident.to_s, newline)
              print value
            else
              dump(object.send(ident), ident.to_s)
            end
          } 
        }
      }
    end    
  end

  def self.dump_value(value)
    case value
      when Time; puts value.strftime(timezone? ? "%F %T (%z)" : "%F %T")
      when Date; puts value.strftime("%F")
    else
      puts value.inspect
    end
  end

  def self.dump_id(object)
    if object.class.to_s.start_with?("#")
      puts "<#{object.object_id}> (Class@<#{object.class.object_id}>)"
    else
      puts "<#{object.object_id}> (#{object.class})"
    end
  end

  def self.dump_reference(object) = puts reference(object)

  # Object-level versions of the class methods
  def dump(...) = Dumps.dump(self, ...)
  def dumps(...) = Dumps.dumps(self, ...)

  # def dump_attr <- doesn't exist here, can be defined in derived classes
  def dump_value(ident) = Dumps.dump_value(self.send(ident))
  def dump_id(...) = Dumps.dump_id(self, ...)
  def dump_reference(...) = Dumps.dump_reference(self, ...)

  def self.overrides?(object, method)
    object.respond_to?(method) && object.method(method).owner != Dumps
  end

private
  def self.capture(&block)
    s = StringIO.new
    saved_stdout = $stdout
    begin
      $stdout = s
      yield
    ensure
      $stdout = saved_stdout
    end
    s.string
  end

  # Include time zone in timestamps
  @@timezone = false

  # Stack of values begin processed
  @@dump_stack = []

  # Map from all known objects to ref. It is cleared at the beginning of the
  # top-level object's #dump method. This allows test programs to check the 
  # when @@dump_stack becomes
  # empty (this happens when the top-level #dump call terminates)
  @@references = {}

  @@anonymous = true

  def self.anonymous? = @@anonymous
  def self.anonymous=(b) @@anonymous = b end

  # Stack and ref methods. These are used to avoid endless recursion when the
  # dump objects contain circular references. It is somewhat expensive, though
  def self.top = @@dump_stack.last
  def self.push(elem) = @@dump_stack.push(elem)
  def self.pop(elem) = @@dump_stack.pop
  def self.empty? = @@dump_stack.empty?
  def self.reset
    @@references = {}
    @@anonymous = true
  end
  def self.reference(object) = @@references[object]
  def self.registered?(object) = @@references.key?(object)

  # Compute reference and register the object in @@references
  def self.register(object, label, index: nil)
    if empty?
      ref = "*#{label}"
    elsif index
      ref = "#{reference(top)}[#{index}]"
    else
      ref = "#{reference(top)}.#{label || object.object_id.to_s}"
    end
    @@references[object] = ref
  end

  # Register object and execute block with object on the top of the stack. If
  # the object is already registered a reference is written and the block is
  # not called
  def self.context(object, label, index: nil, &block)
    reset if empty?
    if registered?(object)
      dump_label(label, false); dump_reference(object)
    else
      register object, label, index: index
      begin
        push object
        yield
      ensure
        pop object
      end
    end
  end

  module Dump__ClassMethods
    def dump_identifiers
      @dump_identifiers ||=
          if const_defined?(:DUMP_NEW, false)
            const_get(:DUMP_NEW)
          else
            (superclass.include?(Dumps) ? superclass.dump_identifiers : []) +
            (const_defined?(:DUMP, false) ? const_get(:DUMP) : []) -
            (const_defined?(:DUMP_EXCLUDE, false) ? const_get(:DUMP_EXCLUDE) : [])
          end.map(&:to_sym)
      @dump_identifiers
    end
  end

  def self.included(klass)
    super
    klass.extend Dump__ClassMethods # Add class method to the including klass
  end
end

