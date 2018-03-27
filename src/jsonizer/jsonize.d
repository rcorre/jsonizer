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
      // filter out inaccessible members, such as those with @disable
      static if (__traits(compiles, mixin("this."~name))) {
        enum isReserved = name.startsWith("__");

        enum isInstanceField =
          __traits(compiles, mixin("this."~name~".offsetof"));

        // the &this.name check makes sure this is not an alias
        enum isInstanceMethod =
          __traits(compiles, mixin("&this."~name)) &&
          isSomeFunction!(mixin("this."~name)) &&
          !__traits(isStaticFunction, mixin("this."~name));

        static if ((isInstanceField || isInstanceMethod) && !isReserved)
          enum include = hasUDA!(mixin("this."~name), uda);
        else
          enum include = false;
      }
      else
        enum include = false;
    }

    enum members = Erase!("this", __traits(allMembers, typeof(this)));
    alias _membersWithUDA = Filter!(include, members);
  }

  template _getUDAs(string name, alias uda) {
      import std.meta : Filter;
      import std.traits : getUDAs;
      enum isValue(alias T) = is(typeof(T));
      alias _getUDAs = Filter!(isValue, getUDAs!(mixin("this."~name), uda));
  }

  template _writeMemberType(string name) {
    import std.meta : Filter, AliasSeq;
    import std.traits : Parameters;
    alias overloads = AliasSeq!(__traits(getOverloads, typeof(this), name));
    enum hasOneArg(alias f) = Parameters!f.length == 1;
    alias setters = Filter!(hasOneArg, overloads);
    void tryassign()() { mixin("this."~name~"=this."~name~";"); }

    static if (setters.length)
      alias _writeMemberType = Parameters!(setters[0]);
    else static if (__traits(compiles, tryassign()))
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

  static import std.json;
  static import jsonizer.common;
  alias _jsonizeIgnoreExtra = ignoreExtra;
  private alias constructor =
    typeof(this) function(std.json.JSONValue,
                          in ref jsonizer.common.JsonizeOptions);
  static constructor[string] _jsonizeCtors;

  static if (is(typeof(this) == class)) {
    static this() {
      import std.traits : BaseClassesTuple, fullyQualifiedName;
      import jsonizer.fromjson;
      enum name = fullyQualifiedName!(typeof(this));
      foreach (base ; BaseClassesTuple!(typeof(this)))
        static if (__traits(hasMember, base, "_jsonizeCtors"))
          base._jsonizeCtors[name] = &_fromJSON!(typeof(this));
    }
  }
}

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

  static assert ([S._membersWithUDA!attr] == ["a", "c", "e", "g"]);
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

  static assert ([Outer._membersWithUDA!attr] == ["a"]);
  static assert ([Outer.Inner._membersWithUDA!attr] == ["b"]);
}

unittest {
  struct attr { string s; }
  struct A {
    mixin JsonizeMe;
    @disable this();
    @disable this(this);
    @attr int a;
  }

  static assert ([A._membersWithUDA!attr] == ["a"]);
}

unittest {
  struct attr { string s; }

  static class A {
    mixin JsonizeMe;
    @attr int a;
    @attr string b() { return "hi"; }
    string c() { return "hi"; }
  }

  static assert ([A._membersWithUDA!attr] == ["a", "b"]);

  static class B : A { mixin JsonizeMe; }

  static assert ([B._membersWithUDA!attr] == ["a", "b"]);

  static class C : A {
    mixin JsonizeMe;
    @attr int d;
  }

  static assert ([C._membersWithUDA!attr] == ["d", "a", "b"]);

  static class D : A {
    mixin JsonizeMe;
    @disable int a;
  }

  static assert ([D._membersWithUDA!attr] == ["b"]);
}

// Validate name conflicts (issue #36)
unittest {
  static struct attr { string s; }
  static struct S {
    mixin JsonizeMe;
    @attr("foo") string name, key;
  }

  static assert([S._membersWithUDA!attr] == ["name", "key"]);
  static assert([S._getUDAs!("name", attr)] == [attr("foo")]);
  static assert([S._getUDAs!("key", attr)] == [attr("foo")]);
}

// #40: Can't deserialize both as exact type and as part of a hierarchy
unittest
{
  import jsonizer.fromjson;
  import jsonizer.tojson;

  static class Base
  {
      mixin JsonizeMe;
      @jsonize("class") string className() { return this.classinfo.name; }
  }
  static class Derived : Base
  {
      mixin JsonizeMe;
  }

  auto a = new Derived();
  auto b = a.toJSON.fromJSON!Derived;
  assert(b !is null);
}
