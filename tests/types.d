/// Types defined for unit testing.
module tests.types;

import jsonizer.jsonize;

version (unittest) {
}
else {
  static assert(0, "Do not include tests dir unless in unit-test mode!");
}

struct PrimitiveStruct {
  mixin JsonizeMe;

  @jsonize {
    int    i;
    ulong  l;
    bool   b;
    float  f;
    double d;
    string s;
  }
}

struct PrivateFieldsStruct {
  mixin JsonizeMe;

  @jsonize private {
    int    i;
    ulong  l;
    bool   b;
    float  f;
    double d;
    string s;
  }
}

struct PropertyStruct {
  mixin JsonizeMe;

  @jsonize @property {
    // getters
    auto i() { return _i; }
    auto b() { return _b; }
    auto f() { return _f; }
    auto s() { return _s; }

    // setters
    void i(int val)    { _i = val; }
    void b(bool val)   { _b = val; }
    void f(float val)  { _f = val; }
    void s(string val) { _s = val; }
  }

  private:
  int    _i;
  bool   _b;
  float  _f;
  string _s;
}

struct ArrayStruct {
  mixin JsonizeMe;

  @jsonize {
    int[] i;
    string[] s;
  }
}

struct NestedArrayStruct {
  mixin JsonizeMe;

  @jsonize {
    int[][] i;
    string[][] s;
  }
}

struct StaticArrayStruct {
  mixin JsonizeMe;

  @jsonize {
    int[3] i;
    string[2] s;
  }

  bool opEquals(StaticArrayStruct other) {
    return i == other.i && s == other.s;
  }
}

struct NestedStruct {
  mixin JsonizeMe;
  @jsonize {
    int i;
    string s;
    Inner inner;
  }

  private struct Inner {
    mixin JsonizeMe;
    @jsonize {
      double d;
      int[] a;
    }
  }

  this(int i, string s, double d, int[] a) {
    this.i = i;
    this.s = s;
    inner = Inner(d, a);
  }
}

struct Nested2 {
  mixin JsonizeMe;
  @jsonize Inner inner;

  private struct Inner {
    mixin JsonizeMe;
    @jsonize int i;
  }
}

struct AliasedTypeStruct {
  mixin JsonizeMe;
  alias Ints = int[];
  @jsonize Ints i;
}

struct CustomCtorStruct {
  mixin JsonizeMe;

  @disable this();

  @jsonize {
    int i;
    float f;

    this(int i, float f) {
      this.i = i;
      this.f = f;
    }
  }
}

class SimpleClass {
  mixin JsonizeMe;
  @jsonize {
    int i;
    string s;
  }
}

class OuterClass {
  mixin JsonizeMe;

  @jsonize {
    int outerVal;
    InnerClass inner;
  }

  class InnerClass {
    mixin JsonizeMe;
    @jsonize int innerVal;

    override bool opEquals(Object obj) {
      auto other = cast(InnerClass) obj;
      return other !is null && this.innerVal == other.innerVal;
    }
  }

  override bool opEquals(Object obj) {
    auto other = cast(OuterClass) obj;
    return other !is null && this.outerVal == other.outerVal;
  }
}

class OuterClassCtor {
  mixin JsonizeMe;

  @jsonize {
    int outerVal;
    InnerClass inner;
  }

  class InnerClass {
    mixin JsonizeMe;
    @jsonize int i;

    @jsonize this(int i) { this.i = i; }
  }

  override bool opEquals(Object obj) {
    auto other = cast(OuterClassCtor) obj;
    return other !is null && outerVal == other.outerVal && inner.i == other.inner.i;
  }
}

struct GenericStruct(T) {
  mixin JsonizeMe;

  @jsonize T val;
}

struct IntStruct {
  mixin JsonizeMe;
  int i;
  @jsonize this(int i) { this.i = i; }
}
