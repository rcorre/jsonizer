/**
  * Enables marking user-defined types for JSON serialization.
  *
  * Authors: <a href="https://github.com/rcorre">rcorre</a>
  * License: <a href="http://opensource.org/licenses/MIT">MIT</a>
  * Copyright: Copyright © 2015, rcorre
  * Date: 3/23/15
  */
module jsonizer.jsonize;

import jsonizer.common;

/**
 * Enable `fromJSON`/`toJSON` support for the type this is mixed in to.
 *
 * In order for fields to be (de)serialized, they must be annotated with
 * `jsonize` (in addition to having the mixin within the type).
 *
 * This mixin will _not_ recursively apply to nested types. If a nested type is
 * to be serialized, it must have `JsonizeMe` mixed in as well.
 * Params:
 *   ignoreExtra = whether to silently ignore json keys that do not map to serialized members
 */
mixin template JsonizeMe(JsonizeIgnoreExtraKeys ignoreExtra = JsonizeIgnoreExtraKeys.yes) {
  static import std.json;

  template _membersWithUDA(uda) {
    import std.meta : Erase, Filter;
    import std.traits : isSomeFunction, hasUDA;
    import std.string : startsWith;

    template include(string name) {
      enum isReserved = name.startsWith("__");

      enum isInstanceField = __traits(compiles, mixin("this."~name~".offsetof"));

      enum isInstanceMethod =
        isSomeFunction!(mixin("this."~name)) &&
        !__traits(isStaticFunction, mixin("this."~name));

      static if ((isInstanceField || isInstanceMethod) && !isReserved)
        enum include = hasUDA!(mixin("this."~name), uda);
      else
        enum include = false;
    }

    enum members = Erase!("this", __traits(allMembers, typeof(this)));

    alias _membersWithUDA = Filter!(include, members);
  }

  template _getUDAs(string name, alias uda) {
      import std.traits : getUDAs;
      alias _getUDAs = getUDAs!(mixin(name), uda);
  }

  template _writeMemberType(string name) {
    import std.meta : Filter, AliasSeq;
    import std.traits : Parameters;
    alias overloads = AliasSeq!(__traits(getOverloads, typeof(this), name));
    enum hasOneArg(alias f) = Parameters!f.length == 1;
    alias setters = Filter!(hasOneArg, overloads);

    static if (setters.length)
      alias _writeMemberType = Parameters!(setters[0]);
    else static if (__traits(compiles, mixin("this."~name~"=this."~name)))
      alias _writeMemberType = typeof(mixin("this."~name));
    else
      alias _writeMemberType = void;
  }

  auto _readMember(string name)() {
      return __traits(getMember, this, name);
  }

  void _writeMember(T, string name)(T val) {
      __traits(getMember, this, name) = val;
  }

  alias _jsonizeIgnoreExtra = ignoreExtra;
}

version (unittest)
  import std.meta : AliasSeq;

unittest {
  static struct attr { string s; }
  static struct S {
    mixin JsonizeMe;
    @attr this(int i) { }
    @attr this(this) { }
    @attr ~this() { }
    @attr int a;
    @attr static int b;
    @attr void c() { }
    @attr static void d() { }
    @attr int e(string s) { return 1; }
    @attr static int f(string s) { return 1; }
    @attr("foo") int g;
    @attr("foo") static int h;
    int i;
    static int j;
    void k() { };
    static void l() { };
    alias Int = int;
    enum s = 5;
  }

  static assert (S._membersWithUDA!attr == AliasSeq!("a", "c", "e", "g"));
}

unittest {
  struct attr { string s; }
  struct Outer {
    mixin JsonizeMe;
    @attr int a;
    struct Inner {
      mixin JsonizeMe;
      @attr this(int i) { }
      @attr this(this) { }
      @attr int b;
    }
  }

  static assert (Outer._membersWithUDA!attr == AliasSeq!("a"));
  static assert (Outer.Inner._membersWithUDA!attr == AliasSeq!("b"));
}

unittest {
  struct attr { string s; }
  struct A {
    mixin JsonizeMe;
    @disable this();
    @disable this(this);
    @attr int a;
  }

  static assert (A._membersWithUDA!attr == AliasSeq!("a"));
}

unittest {
  import std.meta : AliasSeq;

  struct attr { string s; }

  class A {
    mixin JsonizeMe;
    @attr int a;
    @attr string b() { return "hi"; }
    string c() { return "hi"; }
  }

  static assert (A._membersWithUDA!attr == AliasSeq!("a", "b"));

  class B : A { mixin JsonizeMe; }

  static assert (B._membersWithUDA!attr == AliasSeq!("a", "b"));

  class C : A {
    mixin JsonizeMe;
    @attr int d;
  }

  static assert (C._membersWithUDA!attr == AliasSeq!("d", "a", "b"));

  /* TODO -- handle subclass disabling inherited member
  class D : A {
    mixin JsonizeMe;
    @disable int a;
  }

  static assert (D._membersWithUDA!attr == AliasSeq!("b"));
  */
}

/++
// unfortunately these test classes must be implemented outside the unittest
// as Object.factory (and ClassInfo.find) cannot work with nested classes
private {
  class TestComponent {
    mixin JsonizeMe;
    @jsonize int c;
  }

  class TestCompA : TestComponent {
    mixin JsonizeMe;
    @jsonize int a;
  }

  class TestCompB : TestComponent {
    mixin JsonizeMe;
    @jsonize string b;
  }
}

/// type inference
unittest {
  import std.json   : parseJSON;
  import std.string : format;
  import std.traits : fullyQualifiedName;

  // need to use these because unittest is assigned weird name
  // normally would just be "modulename.classname"
  string classKeyA = fullyQualifiedName!TestCompA;
  string classKeyB = fullyQualifiedName!TestCompB;

  assert(Object.factory(classKeyA) !is null && Object.factory(classKeyB) !is null,
      "cannot factory classes in unittest -- this is a problem with the test");

  auto data = `[
    {
      "class": "%s",
      "c": 1,
      "a": 5
    },
    {
      "class": "%s",
      "c": 2,
      "b": "hello"
    }
  ]`.format(classKeyA, classKeyB).parseJSON.fromJSON!(TestComponent[]);

  auto a = cast(TestCompA) data[0];
  auto b = cast(TestCompB) data[1];

  assert(a !is null && a.c == 1 && a.a == 5);
  assert(b !is null && b.c == 2 && b.b == "hello");
}

/// type inference with custom type key
unittest {
  import std.string : format;
  import std.traits : fullyQualifiedName;
  import jsonizer   : fromJSONString;

  // use "type" instead of "class" to identify dynamic type
  JsonizeOptions options;
  options.classKey = "type";

  // need to use these because unittest is assigned weird name
  // normally would just be "modulename.classname"
  string classKeyA = fullyQualifiedName!TestCompA;
  string classKeyB = fullyQualifiedName!TestCompB;

  auto data = `[
    {
      "type": "%s",
      "c": 1,
      "a": 5
    },
    {
      "type": "%s",
      "c": 2,
      "b": "hello"
    }
  ]`.format(classKeyA, classKeyB)
  .fromJSONString!(TestComponent[])(options);

  auto a = cast(TestCompA) data[0];
  auto b = cast(TestCompB) data[1];
  assert(a !is null && a.c == 1 && a.a == 5);
  assert(b !is null && b.c == 2 && b.b == "hello");
}

//test the class map
unittest {
  import std.string : format;
  import std.traits : fullyQualifiedName;
  import jsonizer   : fromJSONString;

  // use "type" instead of "class" to identify dynamic type
  JsonizeOptions options;
  options.classKey = "type";

  // need to use these because unittest is assigned weird name
  // normally would just be "modulename.classname"
  //string classKeyA = fullyQualifiedName!TestCompA;
  //string classKeyB = fullyQualifiedName!TestCompB;

  const string wrongName = "unrelated";

  string[string] classMap = [
    TestCompA.stringof : fullyQualifiedName!TestCompA,
    TestCompB.stringof : fullyQualifiedName!TestCompB,
    wrongName          : fullyQualifiedName!TestCompA
  ];

  options.classMap = delegate string(string rawKey) {
    if(auto val = rawKey in classMap)
      return *val;
    else
      return null;
  };

  auto data = `[
    {
      "type": "%s",
      "c": 1,
      "a": 5
    },
    {
      "type": "%s",
      "c": 2,
      "b": "hello"
    },
    {
      "type": "%s",
      "c": 3,
      "a": 12
    }
  ]`.format(TestCompA.stringof, TestCompB.stringof, wrongName)
  .fromJSONString!(TestComponent[])(options);

  auto a = cast(TestCompA) data[0];
  auto b = cast(TestCompB) data[1];
  auto c = cast(TestCompA) data[2];
  assert(a !is null && a.c == 1 && a.a == 5);
  assert(b !is null && b.c == 2 && b.b == "hello");
  assert(c !is null && c.c == 3 && c.a == 12);
}

// TODO: These are not examples but edge-case tests
// factor out into dedicated test modules

// Validate issue #20:
// Unable to de-jsonize a class when a construct is marked @jsonize.
unittest {
  import std.json            : parseJSON;
  import std.algorithm       : canFind;
  import std.exception       : collectException;
  import jsonizer.jsonize    : jsonize, JsonizeMe;
  import jsonizer.exceptions : JsonizeConstructorException;
  import jsonizer.fromjson   : fromJSON;

  static class A {
    private const int a;

    this(float f) {
      a = 0;
    }

    @jsonize this(int a) {
      this.a = a;
    }

    @jsonize this(string s, float f) {
      a = 0;
    }
  }

  auto ex = collectException!JsonizeConstructorException(`{}`.parseJSON.fromJSON!A);
  assert(ex !is null, "failure to match @jsonize'd constructors should throw");
  assert(ex.msg.canFind("(int a)") && ex.msg.canFind("(string s, float f)"),
    "JsonizeConstructorException message should contain attempted constructors");
  assert(!ex.msg.canFind("(float f)"),
    "JsonizeConstructorException message should not contain non-jsonized constructors");
}

// Validate issue #17:
// Unable to construct class containing private (not marked with @jsonize) types.
unittest {
  import std.json : parseJSON;

  static class A {
    mixin JsonizeMe;

    private int a;

    @jsonize public this(int a) {
        this.a = a;
    }
  }

  auto json = `{ "a": 5}`.parseJSON;
  auto a = fromJSON!A(json);

  assert(a.a == 5);
}

// Validate issue #18:
// Unable to construct class with const types.
unittest {
  import std.json : parseJSON;

  static class A {
    mixin JsonizeMe;

    const int a;

    @jsonize public this(int a) {
        this.a = a;
    }
  }

  auto json = `{ "a": 5}`.parseJSON;
  auto a = fromJSON!A(json);

  assert(a.a == 5);
}

// Validate issue #19:
// Unable to construct class containing private (not marked with @jsonize) types.
unittest {
  import std.json : parseJSON;

  static class A {
    mixin JsonizeMe;

    alias Integer = int;
    Integer a;

    @jsonize public this(Integer a) {
        this.a = a;
    }
  }

  auto json = `{ "a": 5}`.parseJSON;
  auto a = fromJSON!A(json);

  assert(a.a == 5);
}

unittest {
  import std.json : parseJSON;

  static struct A
  {
    mixin JsonizeMe;
    @jsonize int a;
    @jsonize(Jsonize.opt) string attr;
    @jsonize(JsonizeIn.opt) string attr2;
  }

  auto a = A(5);
  assert(a == a.toJSON.fromJSON!A);
  assert(a.toJSON == `{ "a":5, "attr2":"" }`.parseJSON);
  assert(a.toJSON != `{ "a":5, "attr":"", "attr2":"" }`.parseJSON);
  a.attr = "hello";
  assert(a == a.toJSON.fromJSON!A);
  assert(a.toJSON == `{ "a":5, "attr":"hello", "attr2":"" }`.parseJSON);
  a.attr2 = "world";
  assert(a == a.toJSON.fromJSON!A);
  assert(a.toJSON == `{ "a":5, "attr":"hello", "attr2":"world" }`.parseJSON);
  a.attr = "";
  assert(a == a.toJSON.fromJSON!A);
  assert(a.toJSON == `{ "a":5, "attr2":"world" }`.parseJSON);
}

unittest {
  import std.json : parseJSON;

  static struct A
  {
    mixin JsonizeMe;
    @jsonize int a;
    @disable int opEquals( ref const(A) );
  }

  static assert(!is(typeof(A.init==A.init)));

  static struct B
  {
    mixin JsonizeMe;
    @jsonize(Jsonize.opt) A a;
  }

  auto b = B(A(10));
  assert(b.a.a == 10);
  assert(b.a.a == (b.toJSON.fromJSON!B).a.a);
  assert(b.toJSON == `{"a":{"a":10}}`.parseJSON);
  b.a.a = 0;
  assert(b.a.a == int.init );
  assert(b.a.a == (b.toJSON.fromJSON!B).a.a);
  assert(b.toJSON == "{}".parseJSON);
}

unittest {
  import std.json : parseJSON;
  import std.exception;

  static struct T
  {
    mixin JsonizeMe;
    @jsonize(Jsonize.opt)
    {
      int a;
      @jsonize(JsonizeOut.no,JsonizeIn.yes) string b;
      @jsonize(JsonizeOut.yes,JsonizeIn.no) string c;
    }
  }

  auto t = T(5);
  assertThrown(t.toJSON.fromJSON!T);
  assert(t.toJSON == `{ "a":5, "c":"" }`.parseJSON);
  t.b = "hello";
  assert(t == `{ "a":5, "b":"hello" }`.parseJSON.fromJSON!T);
  t.c = "world";
  assert(t.toJSON == `{ "a":5, "c":"world" }`.parseJSON);
  t.a = 0;
  assert(t.toJSON == `{ "c":"world" }`.parseJSON);
  auto t2 = `{ "b":"hello", "c":"okda" }`.parseJSON.fromJSON!T;
  assert(t.a == t2.a);
  assert(t.b == t2.b);
  assert(t2.c == "");
}
++/
