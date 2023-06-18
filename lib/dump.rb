# frozen_string_literal: true

require_relative "dump/version"

require 'indented_io'

module Dump
  class Error < StandardError; end

  # :call-seq:
  #   dump(label, ident, ...)
  #   dump(ident, ...)
  #
  def dump(*args)
    idents = self.class.dump_identifiers + args.select { |arg| !arg.is_a?(String) }
    if label = args.find { |arg| arg.is_a?(String) }
      dump_label(label)
      indent { dump_idents(idents) }
    else
      dump_idents(idents)
    end
  end

  def dumps(*args)
    dump(*args)
    puts
  end

  def dump_idents(idents) = idents.each { |ident| dump_attr(ident, self.send(ident)) }

  def dump_attr(ident, value)
    dump_attr_method = :"dump_attr_#{ident}" # Check if a specialized dump method exists
    if respond_to?(dump_attr_method)
      self.send(dump_attr_method, value)
    else
      dump_value_method = :"dump_value_#{ident}" # Check if a specialized dump method exists
      dump_value_method = :dump_value if !respond_to?(dump_value_method)
      case value
        when {}, []; dump_label(ident, false); self.send(dump_value_method, value)
        when Hash, Array, Dump; dump_label(ident); indent { self.send(dump_value_method, value) }
      else
        dump_label(ident, false); self.send(dump_value_method, value)
      end
    end
  end

  def dump_label(label, newline = true) = print "#{label}:#{newline ? "\n" : " "}"

  def dump_value(value)
    case value
      when {}, []; puts value.inspect
      when Hash; value.each { |k,v| dump_attr(k, v) }
      when Array; value.each { |e| print "- "; indent(bol: false) { dump_value(e) } }
      when Dump; value.dump
    else
      puts value.inspect
    end
  end

  def self.dump(value) = dump_value(value)

  module_function :dump_attr, :dump_label, :dump_value
  public :dump_attr, :dump_label, :dump_value

private
  module Dump__ClassMethods
    def dump_identifiers
      @dump_identifiers ||=
          if const_defined?(:DUMP_NEW, false)
            const_get(:DUMP_NEW)
          else
            (superclass.include?(Dump) ? superclass.dump_identifiers : []) +
            (const_defined?(:DUMP, false) ? const_get(:DUMP) : []) -
            (const_defined?(:DUMP_NOT, false) ? const_get(:DUMP_NOT) : [])
          end.map(&:to_sym)
      @dump_identifiers
    end
  end

  def self.included(klass)
    super
    klass.extend Dump__ClassMethods # Add class method to the including klass
  end
end

