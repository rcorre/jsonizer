/**
  * Internal helper functions/templates.
  *
  * Authors: <a href="https://github.com/rcorre">rcorre</a>
	* License: <a href="http://opensource.org/licenses/MIT">MIT</a>
	* Copyright: Copyright © 2015, rcorre
  * Date: 3/29/15
  */
module jsonizer.internal.util;

import std.typetuple;
import std.traits : ParameterTypeTuple, isBuiltinType, isAssignable;
import jsonizer.internal.attribute;

/// Return members of T that could be serializeable.
/// Use `jsonizeKey` to reduce the result of `filteredMembers` to only members marked for
/// serialization
template filteredMembers(T) {
  enum filteredMembers =
    EraseAll!("_toJSON",
    EraseAll!("_fromJSON",
    EraseAll!("__ctor",
      __traits(allMembers, T))));
}

/// if member is marked with @jsonize("someName"), returns "someName".
/// if member is marked with @jsonize, returns the name of the member.
/// if member is not marked with @jsonize, returns null
/// example usage within a struct/class:
/// enum key = jsonizeKey!(__traits(getMember, this, member), member)
template jsonizeKey(alias member, string defaultName) {
  alias found = findAttribute!(jsonize, member);

  static if (found.length == 0) {
    // no @jsonize attribute found
    enum jsonizeKey = null;
  }
  else static if (isValueAttribute!(found[$ - 1])) {
    // most-nested attribute is @jsonize(args...), key is attr.key
    enum key = found[$ - 1].key;
    enum jsonizeKey = (key is null) ? defaultName : key;
  }
  else {
    // most-nested attribute is @jsonize, no custom key specified
    enum jsonizeKey = defaultName;
  }
}

/// Hack to catch and ignore aliased types.
/// for example, a class contains 'alias Integer = int',
/// it will be redirected to this template and return null (cannot be jsonized)
template jsonizeKey(T, string unused) {
  enum jsonizeKey = null;
}

/// return true if member is marked with @jsonize(JsonizeOptional.yes).
template isOptional(alias member) {
  alias found = Filter!(isValueAttribute, findAttribute!(jsonize, member));

  // find an explicit JsonizeOptional parameter.
  // start with the attribute closest to the member and move outwards.
  template helper(attrs ...) {
    static if (attrs.length == 0) {
      // recursion endpoint, no JsonizeOptional found.
      enum helper = false;
    }
    else static if (attrs[$ - 1].optional == JsonizeOptional.unspecified) {
      // unspecified, recurse to less-nested attribute
      enum helper = helper!(attrs[0 .. $ - 1]);
    }
    else {
      // specified either yes or no, use that value
      enum helper = (attrs[$ - 1].optional == JsonizeOptional.yes);
    }
  }

  enum isOptional = helper!(found);
}

/// Get a tuple of all attributes on `sym` matching `attr`.
template findAttribute(alias attr, alias sym) {
  static assert(__traits(compiles, __traits(getAttributes, sym)),
      "cannot get attributes of " ~ sym.stringof);

  template match(alias a) {
    enum match = (is(a == attr) || is(typeof(a) == attr));
  }

  alias findAttribute = Filter!(match, __traits(getAttributes, sym));
}

unittest {
  struct attr { int i; }
  struct junk { int i; }

  void fun0() { }
  @attr void fun1() { }
  @attr(2) void fun2() { }
  @junk @attr void fun3() { }
  @attr(3) @junk @attr void fun4() { }

  static assert(findAttribute!(attr, fun0).length == 0);
  static assert(findAttribute!(attr, fun1).length == 1);
  static assert(findAttribute!(attr, fun2).length == 1);
  static assert(findAttribute!(attr, fun3).length == 1);
  static assert(findAttribute!(attr, fun4).length == 2);

  struct S0 { }
  @attr struct S1 { }
  @junk @attr struct S { }
  static assert(findAttribute!(attr, S).length == 1);
}

/// True if `sym` has an attribute `attr`.
template hasAttribute(alias attr, alias sym) {
  enum hasAttribute = findAttribute!(attr, sym).length > 0;
}

/// `hasAttribute`
unittest {
  enum attr;

  void fun0() { }
  @attr void fun1() { }

  static assert(!hasAttribute!(attr, fun0));
  static assert( hasAttribute!(attr, fun1));
}

/// True if `attr` has a value (e.g. it is not a type).
template isValueAttribute(alias attr) {
  enum isValueAttribute = is(typeof(attr));
}

/// `isValueAttribute`
unittest {
  struct attr { int i; }

  @attr @attr(3) void fun() { }

  static assert(!isValueAttribute!(__traits(getAttributes, fun)[0]));
  static assert( isValueAttribute!(__traits(getAttributes, fun)[1]));
}

auto getMember(string name)() {
  return (x) => __traits(getMember, x, name);
}

T construct(T, Params ...)(Params params) {
  static if (is(typeof(T(params)) == T)) {
    return T(params);
  }
  else static if (is(typeof(new T(params)) == T)) {
    return new T(params);
  }
  else {
    static assert(0, "Cannot construct");
  }
}

unittest {
  static struct Foo {
    this(int i) { this.i = i; }
    int i;
  }

  assert(construct!Foo().i == 0);
  assert(construct!Foo(4).i == 4);
  assert(!__traits(compiles, construct!Foo("asd")));
}

unittest {
  static class Foo {
    this(int i) { this.i = i; }

    this(int i, string s) {
      this.i = i;
      this.s = s;
    }

    int i;
    string s;
  }

  assert(construct!Foo(4).i == 4);
  assert(construct!Foo(4, "asdf").s == "asdf");
  assert(!__traits(compiles, construct!Foo("asd")));
}

template hasDefaultCtor(T) {
  enum hasDefaultCtor = is(typeof(T()) == T) || is(typeof(new T()) == T);
}

unittest {
  static struct S1 { }
  static struct S2 { this(int i) { } }
  static struct S3 { @disable this(); }

  static class C1 { }
  static class C2 { this(string s) { } }

  static assert( hasDefaultCtor!S1);
  static assert( hasDefaultCtor!S2);
  static assert(!hasDefaultCtor!S3);

  static assert( hasDefaultCtor!C1);
  static assert(!hasDefaultCtor!C2);
}

/// Return all primitive types that are assignable to `T`
template PrimitivesAssignableTo(T) if (is(T == struct)) {
  static if (__traits(hasMember, T, "opAssign")) {
    enum check(K) = isBuiltinType!K && isAssignable!(T, K);

    alias PrimitivesAssignableTo =
      Filter!(check, staticMap!(ParameterTypeTuple, __traits(getOverloads, T, "opAssign")));
  }
  else {
    alias PrimitivesAssignableTo = TypeTuple!();
  }
}

unittest {
  struct S {
    void opAssign(int) { }   // valid opAssign
    void opAssign(float) { } // valid opAssign
    void opAssign(S rhs) { } // elaborate same-type assign
  }

  static struct Q {
    void opAssign(string, string) { }; // not valid opAssign -- not included
    this(float f) { }                  // assignable from float
  }

  static struct P {
    void opAssign(int[]) { }; // array assignment
  }

  static assert(is(PrimitivesAssignableTo!S == TypeTuple!(int, float)));
  static assert(is(PrimitivesAssignableTo!Q == TypeTuple!()));
  static assert(is(PrimitivesAssignableTo!P == TypeTuple!(int[])));
}
