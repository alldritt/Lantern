// Lantern Conformance Test Fixtures — SwiftUI Views
// Verify SwiftUI bridge types work correctly.
// VIEW = expect a ViewBox/hostObject result
// COMPILES = expect no errors (no output check)
// ERROR = expect an error

// === View Constructors ===

// TEST: text_constructor
// EXPECT: VIEW
Text("Hello")
// END

// TEST: spacer_constructor
// EXPECT: VIEW
Spacer()
// END

// TEST: divider_constructor
// EXPECT: VIEW
Divider()
// END

// TEST: image_constructor
// EXPECT: VIEW
Image("star")
// END

// TEST: color_constructor
// EXPECT: VIEW
Color("red")
// END

// === Container Views ===

// TEST: vstack_with_children
// EXPECT: VIEW
VStack {
    Text("A")
    Text("B")
}
// END

// TEST: hstack_with_children
// EXPECT: VIEW
HStack {
    Text("A")
    Text("B")
}
// END

// TEST: zstack_with_children
// EXPECT: VIEW
ZStack {
    Text("Back")
    Text("Front")
}
// END

// TEST: scroll_view
// EXPECT: VIEW
ScrollView {
    Text("Content")
}
// END

// TEST: list_view
// EXPECT: VIEW
List {
    Text("Item 1")
    Text("Item 2")
}
// END

// TEST: navigation_stack
// EXPECT: VIEW
NavigationStack {
    Text("Root")
}
// END

// === Modifier Chains ===

// TEST: text_with_font_enum
// EXPECT: VIEW
Text("Hi").font(.title)
// END

// TEST: text_with_bold
// EXPECT: VIEW
Text("Hi").bold()
// END

// TEST: text_with_color_enum
// EXPECT: VIEW
Text("Hi").foregroundColor(.red)
// END

// TEST: modifier_chain
// EXPECT: VIEW
Text("Styled")
    .font(.headline)
    .bold()
    .padding()
    .foregroundColor(.blue)
// END

// TEST: background_color_enum
// EXPECT: VIEW
Text("Hi").background(.yellow)
// END

// === View Structs ===

// TEST: simple_view_struct
// EXPECT: VIEW
struct MyView: View {
    var body: some View {
        Text("Hello from struct")
    }
}
MyView()
// END

// TEST: view_struct_with_state
// EXPECT: VIEW
struct Counter: View {
    @State var count = 0
    var body: some View {
        VStack {
            Text("\(count)")
            Button("+1") { count = count + 1 }
        }
    }
}
Counter()
// END

// TEST: view_struct_with_containers
// EXPECT: VIEW
struct Layout: View {
    var body: some View {
        VStack {
            HStack {
                Text("Left")
                Spacer()
                Text("Right")
            }
            Divider()
            Text("Bottom")
        }
    }
}
Layout()
// END

// TEST: view_struct_with_modifiers
// EXPECT: VIEW
struct StyledView: View {
    var body: some View {
        Text("Styled")
            .font(.title)
            .bold()
            .foregroundColor(.red)
            .padding()
    }
}
StyledView()
// END

// === Interactive Views ===

// TEST: button_with_title
// EXPECT: VIEW
Button("Tap Me") {
    print("tapped")
}
// END

// TEST: button_with_state
// EXPECT: VIEW
struct BtnView: View {
    @State var x = 0
    var body: some View {
        Button("tap") { x = x + 1 }
    }
}
BtnView()
// END

// === ForEach ===

// TEST: foreach_in_list
// EXPECT: VIEW
List {
    ForEach([1, 2, 3]) { item in
        Text("\(item)")
    }
}
// END

// === Nested Containers ===

// TEST: deeply_nested_view
// EXPECT: VIEW
VStack {
    HStack {
        VStack {
            Text("Deep")
        }
    }
    ZStack {
        Text("Layer")
    }
}
// END
