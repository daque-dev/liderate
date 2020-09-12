module liderate.simplelanx_semantic;

import liderate.simplelanx: parse, Node, TextObject;

import std.conv;
import std.stdio;

public struct SemanticParseResult
{
  Node root;
  string[TextObject] globalId;
  TextObject[string] textObjectById;
  string[][TextObject] referencedBy;
}

public SemanticParseResult semanticParse(string inputString)
{
  SemanticParseResult result;
  result.root = parse(inputString);

  class SemanticError : Throwable
  {
    this(string msg)
    {
      import std.conv;
      super(text("Semantic error: ", msg));
    }
  }
  ulong anonIdCounter = 0;
  void fillGlobalId(Node currentNode, string context)
  {
    void fillGlobalIdTextObject(TextObject to, string context)
    {
      if (to.isPlainText) return;
      if (to.id is null)
        {
          string id = text("__anonId", anonIdCounter++);

          result.globalId[to] = id;
          result.textObjectById[id] = to;
        }
      else
        {
          string id = context ~ to.id;
          assert(to !in result.globalId); // TODO throw exception
          result.globalId[to] = id;
          assert(id !in result.textObjectById); // TODO throw exception instead of failure
          result.textObjectById[id] = to;
        }
      foreach(component; to.components)
        {
          fillGlobalIdTextObject(component, context);
        }
    }
    
    foreach(textObject; currentNode.objects)
      fillGlobalIdTextObject(textObject, context);
    
    if (currentNode.objects.length == 1 &&
	currentNode.objects[0].name == "section")
      context ~= currentNode.objects[0].id ~ "/";

    foreach(child; currentNode.children)
      {
        fillGlobalId(child, context);
      }
  }
  void countReferences(Node node)
  {
    void countReferencesTextObject(TextObject object)
    {
      if (object.name == "ref")
        {
          auto referenced = object.components[0].name;
          if (referenced !in result.textObjectById)
            {
              assert(0, text("Reference to object ", referenced, " which doesn't exist"));
            }
          auto referencedObject = result.textObjectById[referenced];
          result.referencedBy.require(referencedObject, null) ~= result.globalId[object];
          return;
        }
      foreach(component; object.components)
        {
          countReferencesTextObject(component);
        }
    }

    foreach(object; node.objects)
      {
        countReferencesTextObject(object);
      }

    foreach(child; node.children)
      {
        countReferences(child);
      }
  }

  debug void printResult(Node node, int indent)
  {
    void printTextObject(TextObject textObject)
    {
      if (textObject.isPlainText)
	{
	  write(textObject.name, " ");
	  return;
	}
      write(`[`);
      write(textObject.name);
      write("#");
      write(textObject.id);
      write("$");
      write(result.globalId[textObject]);
      write("] ");
      if (auto references = textObject in result.referencedBy)
        {
          write("<-{");
          foreach(reference; *references)
            {
              write(reference, " ");
            }
          write("}");
        }
      if (textObject.components.length > 0)
        write("{");
      foreach(component; textObject.components)
        printTextObject(component);
      if (textObject.components.length > 0)
        write("} ");
    }
    foreach(i; 0 .. indent) write(' ');
    write("Node: ");
    foreach(textObject; node.objects)
      {
        printTextObject(textObject);
      }
    writeln;

    foreach(child; node.children)
      {
        printResult(child, indent + 2);
      }
  }
  
  debug writeln("checking root node"); checkNode(result.root);
  debug writeln("globalizing references"); globalizeReferences(result.root, "");
  debug writeln("filling global ids"); fillGlobalId(result.root, "");
  debug writeln("doing reference counting"); countReferences(result.root);
  debug writeln("cheking modified root node"); checkNode(result.root);
  return result;
}

private void checkNode(Node node)
{
  foreach(textObject; node.objects)
    checkTextObject(textObject, cast(int) node.objects.length);
  foreach(child; node.children)
    checkNode(child);
}

private void checkTextObject(TextObject textObject, int noSiblings)
{
  if (textObject.isPlainText)
    {
      assert(textObject.components is null);
      assert(textObject.id is null);
      return;
    }
  switch(textObject.name)
    {
    case "section":
      assert(noSiblings == 1);
      break;
    case "ref":
      assert(textObject.components.length == 1 &&
             textObject.components[0].isPlainText);
      break;
    case "equation":
      assert(noSiblings == 1);
      break;
    case "remark":
      break;
    default:
      break;
    }
  foreach(component; textObject.components)
    checkTextObject(component, 1);
}

private void globalizeReferences(Node node, string context)
{
  foreach(textObject; node.objects)
    globalizeReferences(textObject, context);
  if (node.objects.length == 1 &&
      node.objects[0].name == "section")
    context = context ~ node.objects[0].id ~ "/";
  foreach(child; node.children)
    globalizeReferences(child, context);
}

private void globalizeReferences(TextObject textObject, string context)
{
  if (textObject.name == "ref")
    {
      auto refText = textObject.components[0].name;
      if (refText[0] == '/') // if it is global id
	return;
      textObject.components[0].name = context ~ refText;
      return;
    }
  foreach(component; textObject.components)
    globalizeReferences(component, context);
}
