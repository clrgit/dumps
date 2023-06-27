
# A named bare test classi, all other test classes are anonymous. Only used to
# test dump of classes without attributes
module Dump__RSpecModule
  class A
    include Dumps
    attr_reader :a
  end
end

describe Dumps do
  # Catch block's stdout and compare to 's'
  def check(s, &block) = expect(&block).to output(ltrim(s)).to_stdout

  # Check #dump_value
  def check_value(res, value) = check(res) { Dumps.dump_value(value) }

  # Check #dump
  def check_dump(res, value, *args, **opts) = check(res) { Dumps.dump(value, *args, **opts) }

  # Check expected error
  def check_error(value, *args, **opts)
    expect { silent { Dumps.dump(value, *args, **opts) } }.to raise_error Constrain::MatchError
  end

  # Check no error
  def check_no_error(value, *args, **opts)
    expect { silent { Dumps.dump(value, *args, **opts) } }.not_to raise_error
  end

  # Disable stdout before yielding to block
  def silent(&block)
    saved_stdout = $stdout
    begin
      $stdout = File.open("/dev/null", "a")
      yield
    ensure
      $stdout = saved_stdout
    end
  end

  # ltrim a block of text. It is used to normalize indented %(...) constructs
  # so they're comparable with output on stdout
  def ltrim(s)
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

  # Class with DUMP defined
  let(:klass) { 
    Class.new do
      include Dumps
      attr_accessor :a, :b
      def initialize(a = 1, b = 2) @a, @b = a, b end
      const_set(:DUMP, [:a, :b]) 
    end
  }
  
  # Sub-class with DUMP defined
  let(:subklass) {
    Class.new(klass) do
      attr_accessor :c
      def initialize(a = 1, b = 2, c = 3)
        super a, b
        @c = c
      end
      const_set(:DUMP, [:c])
    end
  }

  # Bare Dumps class without any DUMP constants
  let(:bareklass) { 
    Class.new do
      include Dumps
      attr_accessor :a, :b
      def initialize(a = 1, b = 2) @a, @b = a, b end
    end
  }

  it 'has a version number' do
    expect(Dumps::VERSION).not_to be_nil
  end

  describe "#dump" do
    it "dumps simple values using #inspect" do
      check_dump '"Hello"', "Hello"
      check_dump 'true', true
    end
    it "supports Time with time zone" do
      begin
        Dumps.timezone = true
        t = Time.new(1970, 1, 2, 3, 4, 5, 0)
        res = "1970-01-02 03:04:05 (+0000)"
        check_dump res, t
      ensure
        Dumps.timezone = false
      end
    end
    it "supports Time without time zone" do
      t = Time.new(1970, 1, 2, 3, 4, 5)
      res = "1970-01-02 03:04:05"
      check_dump res, t
    end
    it "supports Date" do
      d = Date.new(1970, 1, 2)
      res = "1970-01-02"
      check_dump res, d
    end
    it "supports arrays" do
      a = [1, 2, 3]
      res = %(
        - 1
        - 2
        - 3
      )
      check_dump res, a
    end
    it "supports multi-level arrays" do
      a = [1, [2, 3]]
      res = %(
        - 1
        - - 2
          - 3
      )
      check_dump res, a
    end
    it "supports hashes" do
      h = { a: 1, b: 2 }
      res = %(
        a: 1
        b: 2
      )
      check_dump res, h  
    end
    it "supports multi-level hashes" do
      h = { a: 1, b: { c: 2, d: 3} }
      res = %(
        a: 1
        b: 
          c: 2
          d: 3
      )
      check_dump res, h  
    end
    it "supports Dump objects" do
      obj = klass.new
      res = %(
        a: 1
        b: 2
      )
      check_dump res, obj, nil
    end
    it "supports nested Dump objects" do
      subobj = klass.new(2, 3)
      obj = klass.new(1, subobj)
      res = %(
        a: 1
        b: 
          a: 2
          b: 3
      )
      check_dump res, obj, nil
    end
    it "supports nested bare Dump objects" do
      subobj = bareklass.new(2, 3)
      obj = bareklass.new(1, subobj)
      res = %(
        a: 1
        b: <#{subobj.object_id}> (Class@<#{bareklass.object_id}>)
      )
      check_dump res, obj, nil, :a, :b
    end
    it "supports Dump objects with inherited attributes" do
      obj = subklass.new
      res = %(
        a: 1
        b: 2
        c: 3
      )
      check_dump res, obj, nil
    end
    it "supports other classes" do
      obj = Dump__RSpecModule::A.new
      res = %(
        <#{obj.object_id}> (#{obj.class})
      )
      check_dump(res, obj)
    end

    context "with a list of arguments" do
      context "array objects support" do
        it "a list of indexes" do
          a = [1, 2, 3]
          res = %(
            - 1
            - 3
          )
          check_dump res, a, 0, 2
        end
        it "a list of ranges" do
          a = [1, 2, 3, 4, 5]
          res = %(
            - 2
            - 3
            - 4
          )
          check_dump res, a, 1..3
        end
        it "a list of indexes or ranges" do
          a = [1, 2, 3, 4, 5, 6, 7]
          res = %(
            - 1
            - 3
            - 4
            - 5
            - 7
          )
          check_dump res, a, 0, 2..4, 6
        end
      end
      context "hash objects support" do
        it "a list of keys" do
          h = { a: 1, b: 2, c: 3 }
          res = %(
            a: 1
            c: 3
          )
          check_dump res, h, :a, :c
        end
      end

      context "Dump objects support" do
        it "a list of identifiers" do
          obj = bareklass.new
          res = %(
            a: 1
            b: 2
          )
          check_dump res, obj, nil, :a, :b
        end
      end
    end

    context "with a label argument" do
      it "prefixes simple types" do
        check_dump 'a: "Hello"', "Hello", "a"
      end
      it "prefix and indents arrays" do
        l = "a"
        a = [1, 2]
        res = %(
          a:
            - 1
            - 2
        )
        check_dump(res, a, l)
      end
      it "prefix and indents hashes" do
        l = "a"
        h = { b: 1, c: 2 }
        res = %(
          a:
            b: 1
            c: 2
        )
        check_dump(res, h, l)
      end
      it "prefix and indents objects" do
      obj = bareklass.new(1, 2)
      res = %(
        obj:
          a: 1
          b: 2
      )
      check_dump res, obj, "obj", :a, :b
      end
    end

    context "with the :new option" do
      it "raise unless object is a Dump object" do
        check_error [], new: true
        check_no_error klass.new, new: true
      end
      it "raise unless new is true or false" do
        obj = klass.new
        check_error obj, nil, new: 42
        check_no_error obj, nil, new: true
        check_no_error obj, nil, new: false
      end
      it "it overrides declared attributes" do
        obj = klass.new
        res = %(
          b: 2
        )
        check_dump(res, obj, nil, :b, new: true)
      end
      it "it overrides inherited attributes" do
        obj = subklass.new
        res = %(
          b: 2
        )
        check_dump(res, obj, nil, :b, new: true)
      end
    end

    context "with the :exclude option" do
      it "raise unless object is a Dump object" do
        check_error [], exclude: nil
        check_no_error klass.new, new: true
      end
      it "raise unless new is true or false" do
        obj = klass.new
        check_error obj, nil, new: 42
        check_no_error obj, nil, new: true
        check_no_error obj, nil, new: false
      end
    end

    context "with a duplicate object" do
      it "emits a placeholder" do
        obj = klass.new
        sub = klass.new
        obj.a = obj.b = sub
        res = %(
          a:
            a: 1
            b: 2
          b: *.a
        )
        check_dump(res, obj)
      end
    end

    context "with circular references" do
      it "emits a placeholder" do
        obj = klass.new
        obj.b = obj
        res = %(
          a: 1
          b: *
        )
        check_dump(res, obj)
      end
    end

    context "references" do
      let(:obj) { klass.new(sub, 0) }
      let(:sub) { klass.new(subsub, 1) }
      let(:subsub) { klass.new(nil, 2) }
      
      # Initialize Dumps internal datastructures
      before(:each) { silent { obj.dump } }
      
      it "anonymous top-level objects are represented by '*'" do
        silent { obj.dump }
        expect(Dumps.reference(obj)).to eq "*"
        expect(Dumps.reference(sub)).to eq "*.a"
        expect(Dumps.reference(subsub)).to eq "*.a.a"
      end
        
      it "named top-level objects are represented by their name" do
        silent { obj.dump "obj" }
        expect(Dumps.reference(obj)).to eq "*obj"
        expect(Dumps.reference(sub)).to eq "*obj.a"
        expect(Dumps.reference(subsub)).to eq "*obj.a.a"
      end

      it "array elements are represented by index" do
        sub = klass.new(1)
        obj = klass.new([sub, subsub], 0)
        silent { obj.dump }
        expect(Dumps.reference(sub)).to eq "*.a[0]"
        expect(Dumps.reference(subsub)).to eq "*.a[1]"
      end
    end
  end

  describe "#dump_attr" do
    it "overrides all output of attributes" do
      override = Class.new(klass) do
        def dump_attr(ident) = puts "<<#{ident}>>: #{self.send(ident)}"
      end
      obj = override.new
      res = %(
        <<a>>: 1
        <<b>>: 2
      )
      check_dump(res, obj)
    end
  end

  describe "#dump_attr_<ident>" do
    it "overrides the output of the given attributes" do
      override = Class.new(klass) do
        def dump_attr_a = puts "<<a>>: #{a}"
      end
      obj = override.new
      res = %(
        <<a>>: 1
        b: 2
      )
      check_dump(res, obj)
    end
  end

  describe "#dump_value" do
    it "overrides all output of all attribute values" do
      override = Class.new(klass) do 
        def dump_value(ident) = puts "<<#{self.send(ident)}>>"
      end
      obj = override.new
      res = %(
        a: <<1>>
        b: <<2>>
      )
      check_dump(res, obj)
    end
  end

  describe "#dump_value_<ident>" do
    it "overrides output of the given attribute's value" do
      override = Class.new(klass) do 
        def dump_value_a() = puts "<<#{a}>>"
      end
      obj = override.new
      res = %(
        a: <<1>>
        b: 2
      )
      check_dump(res, obj)
    end
  end

  describe "::dump_identifiers" do
    let(:a) {
      Class.new do
        include Dumps
        attr_reader :a
        const_set(:DUMP, [:a]) 
      end
    }
    let(:b) {
      Class.new(a) do
        include Dumps
        attr_reader :b
        const_set(:DUMP, [:b]) 
      end
    }
    let(:c) {
      Class.new(b) do
        include Dumps
        attr_reader :c
        const_set(:DUMP_NEW, [:c, :a]) 
      end
    }
    let(:d) {
      Class.new(c) do
        include Dumps
        attr_reader :d
        const_set(:DUMP, [:d]) 
        const_set(:DUMP_EXCLUDE, [:a]) 
      end
    }

    it "returns a list of declared identifiers" do
      expect(a.dump_identifiers).to eq [:a]
    end

    it "DUMP appends the indentifiers" do
      expect(b.dump_identifiers).to eq [:a, :b]
    end

    it "DUMP_NEW assigns a new list of identifiers" do
      expect(c.dump_identifiers).to eq [:c, :a]
    end

    it "DUMP_EXCLUDE excludes identifiers" do
      expect(d.dump_identifiers).to eq [:c, :d]
    end
  end
end

