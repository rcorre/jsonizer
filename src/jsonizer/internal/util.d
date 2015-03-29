/**
  * Internal helper functions/templates.
  *
  * Authors: <a href="https://github.com/rcorre">rcorre</a>
	* License: <a href="http://opensource.org/licenses/MIT">MIT</a>
	* Copyright: Copyright © 2015, rcorre
  * Date: 3/29/15
  */
module jsonizer.internal.util;

import std.typetuple : EraseAll;
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
  static string helper() {
    static if (__traits(compiles, __traits(getAttributes, member))) {
      foreach(attr ; __traits(getAttributes, member)) {
        static if (is(attr == jsonize)) { // @jsonize someMember;
          return defaultName;             // use member name as-is
        }
        else static if (is(typeof(attr) == jsonize)) { // @jsonize("someKey") someMember;
          return (attr.key is null) ? defaultName : attr.key;
        }
      }
    }

    return null;
  }

  enum jsonizeKey = helper;
}

/// Hack to catch and ignore aliased types.
/// for example, a class contains 'alias Integer = int',
/// it will be redirected to this template and return null (cannot be jsonized)
template jsonizeKey(T, string unused) {
  enum jsonizeKey = null;
}

/// return true if member is marked with @jsonize(JsonizeOptional.yes).
template isOptional(alias member) {
  static bool helper() {
    static if (__traits(compiles, __traits(getAttributes, member))) {
      // start with most nested attribute and move up, looking for a JsonizeOptional tag
      foreach_reverse(attr ; __traits(getAttributes, member)) {
        static if (is(typeof(attr) == jsonize)) {
          final switch (attr.optional) with (JsonizeOptional) {
            case unspecified:
              continue;
            case no:
              return false;
            case yes:
              return true;
          }
        }
      }
    }
    return false;
  }

  enum isOptional = helper;
}
