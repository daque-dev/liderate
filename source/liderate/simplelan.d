module liderate.simplelan;

import std.variant: Algebraic;
import std.traits: EnumMembers;

enum NodeType: string
  {
    simpleLine = ".",
    section = "*",
    fragmentDefinition = "=",
    fileFragmentDefinition = ":=",
    fragmentAddition = "+",
    reference = ">",
    invalid = " "
  }
struct NumberedLine
{
  long lineNumber;
  string content;
}
struct NodeTypeInfo
{
  bool hasChildren = false;
  NodeType[] acceptableChildren = null;
  bool requiresId = false;
}
enum NodeTypeInfo[NodeType] nodeTypeInfo = [
                                            NodeType.simpleLine:
                                            NodeTypeInfo(false),
                                            NodeType.section:
                                            NodeTypeInfo(true,
                                                         [NodeType.simpleLine,
                                                          NodeType.section,
                                                          NodeType.fragmentDefinition,
                                                          NodeType.fragmentAddition,
                                                          NodeType.fileFragmentDefinition],
                                                         true),
                                            NodeType.fragmentDefinition:
                                            NodeTypeInfo(true, [NodeType.simpleLine], true),
                                            NodeType.fileFragmentDefinition:
                                            NodeTypeInfo(true, [NodeType.simpleLine], true),
                                            NodeType.fragmentAddition:
                                            NodeTypeInfo(true, [NodeType.simpleLine, NodeType.reference]),
                                            NodeType.reference:
                                            NodeTypeInfo(false),
                                            ];

class ParseError: Throwable
{
  this(string msg)
  {
    super(msg);
  }
}
class Node
{
public:
  this() // init as root node
  {
    _indentationLevel = -1;
    _type = NodeType.section;
    _value = "";
    _id = "root";
    _children = null;
  }
  this(NumberedLine numberedLine)
  {
    import std.conv: text;
    import std.range: popFront, front, empty;
    import std.algorithm: findSplitBefore, until, find, map, sum, any, filter, startsWith;
    import std.array: array, join, split;
    import std.utf: toUTF8, toUTF32;
    import std.functional: not;
    import std.uni: isWhite;

    assert(numberedLine.content.length > 0 && numberedLine.content.any!(not!isWhite));

    long getIndentationLevel(dchar c)
    {
      switch(c)
        {
        case ' ':
          return 1;
        case '\t':
          return 4;
        default:
          throw new ParseError(text("at ", numberedLine.lineNumber, " unknown whitespace character"));
        }
    }
    NodeType getNodeType(string keyword)
    {
      static foreach(nodeType; EnumMembers!NodeType)
        {
          if (nodeType[] == keyword[])
            return nodeType;
        }
      return NodeType.invalid;
    }

    string indentation = numberedLine.content.until!(not!isWhite).array.toUTF8;
    _indentationLevel = indentation.map!getIndentationLevel.sum;
    string unindentedLine = numberedLine.content.find!(not!isWhite).array.toUTF8;
    string[] asWords = unindentedLine.split;
    assert(asWords.length > 0);
    string keyword = asWords[0];
    auto nodeType = getNodeType(keyword);
    if (nodeType == NodeType.invalid)
      {
        _type = NodeType.simpleLine;
        _value = unindentedLine.dup;
        _id = null;
        _children = null;
      }
    else
      {
        string value = asWords[1 .. $].filter!(word => !word.startsWith("#")).join(" ");
        string[] id = asWords[1 .. $].filter!(word => word.startsWith("#")).map!(id => id[1 .. $]).array;
        if (id.length > 1)
          throw new ParseError("More than one id given");
        _type = nodeType;
        _value = value;
        _id = id.length > 0? id[0] : null;
        _children = null;
      }
    assert(_type != NodeType.invalid);
    assert(_type in nodeTypeInfo);
    if (nodeTypeInfo[_type].requiresId && _id is null)
      throw new ParseError(text(cast(string) _type, " requires id but none has been given"));
  }
  long indentationLevel()
  {
    return _indentationLevel;
  }
  NodeType type()
  {
    return _type;
  }
  void insertChild(Node node)
  {
    import std.algorithm: canFind;
    import std.conv: text;

    assert(node.indentationLevel > this.indentationLevel);

    assert(_type in nodeTypeInfo);
    auto typeInfo = nodeTypeInfo[_type];
    if (!typeInfo.hasChildren || !typeInfo.acceptableChildren.canFind(node.type))
      throw new ParseError(text(cast(string)_type, " can't have ", cast(string) node.type, " as a child"));
    _children ~= node;
  }

  void globalize(string context)
  {
    final switch(_type)
      {
      case NodeType.simpleLine:
        import std.array;
        import std.algorithm;
        auto words = _value.split(" ").filter!(word => word.length > 0);
        _value = words
          .map!((word)
                {
                  if (!word.startsWith("#"))
                    return word;
                  auto refStr = word[1 .. $];
                  if (refStr.startsWith("/"))
                    return word;
                  return "#" ~ context ~ refStr;
                })
          .join(" ");
        return;
      case NodeType.section:
        return;
      case NodeType.fragmentDefinition:
      case NodeType.fileFragmentDefinition:
        if (_id[0] == '/')
          return;
        _id = context ~ _id;
        return;
      case NodeType.fragmentAddition:
      case NodeType.reference:
        if (_value[0] == '/')
          return;
        _value = context ~ _value;
        return;
      case NodeType.invalid:
        assert(0);
      }
  }

  override string toString()
  {
    import std.conv: text;
    string res = "";
    void dfs(Node node, long indentation)
    {
      foreach(i; 0 .. indentation) res ~= " ";
      res ~= text("Node(", node._indentationLevel, " ", cast(string) node._type, " '", node._value, "' ", node._id, ")\n");
      foreach(child; node._children)
        {
          dfs(child, indentation + 4);
        }
    }
    dfs(this, 0);
    return res;
  }

  string id()
  {
    return _id;
  }
  string value()
  {
    return _value;
  }
  auto children()
  {
    return _children;
  }
private:
  long _indentationLevel = -1;
  NodeType _type = NodeType.invalid;
  string _value = null;
  string _id = null;
  Node[] _children = null;
}

Node parseLine(NumberedLine line)
{
  import std.uni: isWhite;
  import std.algorithm: all;
  import std.range: popFront, front, empty;
  if (line.content.empty || line.content.all!isWhite)
    return null;
  return new Node(line);
}

import std.container: SList;
void parseString(out Node root, out SList!Node fragmentNodes, string str)
{
  import std.array: split, join;
  import std.container: SList;
  import std.range: popFront;
  auto lines = str.split("\n");
  root = new Node();
  fragmentNodes = SList!Node();
  auto parentStack = SList!Node(root);
  auto sectionContext = "/";
  foreach(i, line; lines)
    {
      auto node = parseLine(NumberedLine(i + 1, line));
      if (node is null)
        continue;
      final switch(node.type)
        {
        case NodeType.simpleLine:
        case NodeType.section:
        case NodeType.reference:
          break;
        case NodeType.fragmentDefinition:
        case NodeType.fileFragmentDefinition:
        case NodeType.fragmentAddition:
          fragmentNodes.insertFront(node);
          break;
        case NodeType.invalid:
          assert(0);
        }
      long removed = 0;
      while(parentStack.front.indentationLevel >= node.indentationLevel)
        {
          parentStack.removeFront;
          removed++;
        }
      import std.conv: text;
      import std.algorithm: filter, map, reverse;
      import std.array: array;
      import std.stdio;
      sectionContext = "/" ~ parentStack[].array.reverse[1 .. $].map!(n => n.type == NodeType.section? n.id ~ "/" : "").join;
      node.globalize(sectionContext);
      parentStack.front.insertChild(node);
      if (nodeTypeInfo[node.type].hasChildren)
        parentStack.insertFront(node);
      if (node.type == NodeType.section)
        sectionContext ~= node.id ~ "/";
    }
}
