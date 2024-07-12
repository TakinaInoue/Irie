# Irie, the programming language.. sort of?
Hi so, for the past few moments I've been wanting to code a language designed for backend servers
that don't always have the same architecture, sometimes servers are being transitioned from one
architectue to another.
The idea for irie is to create a portable language that just by simply having the IrieVM, you'll already
have support for every irie server software out there.

## The current state
This isn't the proper implementation of irie, it's more or so a huge draft since irie does a lot of
things I have never did in my life, so understand that much of how the IVM and the compiler was done here
will soon change.

## The Language
Irie is a language based off Haxe and Java, with a touch of D.
Unlike JS and other scripting languages, all irie modules require a main function to have any executable code,
let's see an example of a "hello, world":

```ts
import irie.stdio;

function _start() : void {
  println("Hello, World");
}  
```

Notice how the module `irie.stdio` needed to be imported in order to use the println function.
Also, this language is statically typed with some light type inference for variables, here's an example of every
datatype as variables:

```ts
function _start() : void {
  var num  : int = 0;
  var fnum : float = 4.2;
  var bld  : bool = true;
  var str  : string = "hi there!";
  var array : int[] = [4,3,2,1];

  var inference = 4;

  println(typeof inference);
}
```

### Note on variables:
As of now Irie only supports 32 bit values, with strings and arrays being objects.
Note: currently irie does not automatically delete unnecessary objects, nor does it provide a way to delete them.

### Loops and if-statements
I'm yet to code a proper for loop, currently irie allows for while loops and if statements with a C-syntax, the parenthesis around the condition expression are optional.

### Extra syntax related information
Semicolons are optional, and function definitions require the return type to explicitally stated for now.
Import statements convert their module names into paths, so if you type "import irie.stdio", the compiler will convert it into "irie/stdio.irie", and look
for it in two directories: "lib/" on the VM's folder, and "./" (the folder you executed irie in).

For all avaliable standard libraries, check the lib/ directory.
