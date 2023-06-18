
# Dynamic class definition emits a warning so we do it statically and pack
# it into a hopefully unique namespace
module Dump__RSpecModule
  class A
    include Dump
    attr_reader :a
    DUMP = [:a]
  end
  class B < A
    attr_reader :b
    DUMP = [:b]
  end
  class C < B
    attr_reader :c
    DUMP_NEW = [:c, :a]
  end
  class D < C
    attr_reader :d
    DUMP = [:d]
    DUMP_NOT = [:a]
  end
end

describe Dump do
  def undent(s)
    lines = s.split(/\n/)
    lines.shift while !lines.empty? && !(lines.first =~ /^(\s*)\S/)
    return "" if lines.empty?
    indent = $1.size
    r = []
    while line = lines.shift&.rstrip
      r << (line[indent..-1] || "")
    end
    while !r.empty? && r.last =~ /^\s*$/
      r.pop
    end
    r.join("\n") + "\n"
  end

  it 'has a version number' do
    expect(Dump::VERSION).not_to be_nil
  end

  let(:klass) { 
    Class.new do
      include Dump
      attr_reader :a, :b
      def initialize(a = 1, b = 2) @a, @b = a, b end
    end
  }

  def check(s, &block)
    expect(&block).to output(undent(s)).to_stdout
  end

  describe "#dump" do
    it "dumps the given attributes" do
      obj = klass.new("Hello", 42)
      res = %(
        a: "Hello"
        b: 42
      )
      check(res) { obj.dump :a, :b }
    end

    it "handles hashes" do
      obj = klass.new({}, { key: "value" })
      res = %(
        a: {}
        b: 
          key: "value"
      )
      check(res) { obj.dump :a, :b }
    end

    it "handles arrays" do
      obj = klass.new([], %w(Hello World))
      res = %(
        a: []
        b: 
          - "Hello"
          - "World"
      )
      check(res) { obj.dump :a, :b }
    end

    it "preprends ::dump_identifiers" do
      subklass =
          Class.new(klass) do
            attr_reader :c
            def initialize
              super 1, 2
              @c = 3
            end
          end
      subklass.const_set(:DUMP, [:c]) # Class.new differs from 'class ...'
      obj = subklass.new
      res = %(
        c: 3
        a: 1
        b: 2
      )
      check(res) { obj.dump :a, :b }
    end

    context "with a label argument" do
      let(:res) {
        %(
          obj:
            a: 1
            b: 2
        )
      }
      it "dumps the label if given" do
        obj = klass.new
        check(res) { obj.dump "obj", :a, :b }
      end

      it "the label can be anywhere in the arguments" do
        obj = klass.new
        check(res) { obj.dump :a, "obj", :b }
      end

      it "uses the first of multiple labels" do
        obj = klass.new
        check(res) { obj.dump :a, "obj", :b, "not-used" }
      end
    end
  end

  describe "#dump customizations" do
    let(:subklass) {
      Class.new(klass) do
        attr_reader :c
        def initialize(a = 1, b = 2, c = 3)
          super(a, b)
          @c = c
        end
        def dump = super(:a, :b, :c)
      end
    }

    it "customizes the list of attributes" do
      obj = subklass.new(1, 2, 3)
      res = %(
        a: 1
        b: 2
        c: 3
      )
      check(res) { obj.dump }
    end

    it "handles nested objects" do
      subobj = subklass.new(11, 22, 33)
      obj = klass.new(1, subobj)
      res = %(
        a: 1
        b: 
          a: 11
          b: 22
          c: 33
      )
      check(res) { obj.dump :a, :b }
    end
  end

  describe "#dump_attr customizations" do
    let(:subklass) {
      Class.new(klass) do
        def dump_attr_b(value)
          puts "B: <#{value}>"
        end
      end
    }
    
    it "allows for per-attribute customizations" do
      obj = subklass.new(1, 2)
      res = %(
        a: 1
        B: <2>
      )
      check(res) { obj.dump :a, :b }
    end
  end

  describe "#dump_value customizations" do
    let(:subklass) {
      Class.new(klass) do
        def dump_value_b(value)
          puts "<#{value}>"
        end
      end
    }
    
    it "allows for per-attribute customization" do
      obj = subklass.new(1, 2)
      res = %(
        a: 1
        b: <2>
      )
      check(res) { obj.dump :a, :b }
    end
  end

  describe "::dump" do
    it "handles hashes" do
      res = %(
        aa: 11
        bb: 22
      )
      check(res) { Dump.dump({ aa: 11, bb: 22 }) }
    end
    it "handles arrays" do
      res = %(
        - 1
        - 2
        - 3
      )
      check(res) { Dump.dump([1, 2, 3]) }
    end
    it "handles objects" do
      subklass = Class.new(klass) do
        def dump = super(:a, :b)
      end
      obj = subklass.new(1, 2)
      res = %(
        a: 1
        b: 2
      )
      check(res) { Dump.dump(obj) }
    end
    it "handles simple values" do
      check('"Hello"') { Dump.dump("Hello") }
      check("true") { Dump.dump(true) }
      check("42") { Dump.dump(42) }
    end
  end

  describe "::dump_identifiers" do
    let(:a) { Dump__RSpecModule::A }
    let(:b) { Dump__RSpecModule::B }
    let(:c) { Dump__RSpecModule::C }
    let(:d) { Dump__RSpecModule::D }

    it "returns a list of declared identifiers" do
      expect(a.dump_identifiers).to eq [:a]
    end

    it "DUMP appends the indentifiers" do
      expect(b.dump_identifiers).to eq [:a, :b]
    end

    it "DUMP_NEW assigns a new list of identifiers" do
      expect(c.dump_identifiers).to eq [:c, :a]
    end

    it "DUMP_NOT excludes identifiers" do
      expect(d.dump_identifiers).to eq [:c, :d]
    end
  end
end

