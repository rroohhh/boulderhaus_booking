import 'package:flutter/material.dart';
import 'package:async/async.dart';
import 'dart:math';
import 'api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CookieManager.init();

  runApp(App());
}

const pageWidthCm = 10.0;

double centimeterToPixel(BuildContext context, double cm) {
  var ratio = MediaQuery.of(context).devicePixelRatio * 160 / 2.54;
  return min(cm * ratio, MediaQuery.of(context).size.width - 20);
}

const api = BoulderhausAPI();

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var loginStatus = api.loginStatus();

    return MaterialApp(
      title: 'Boulderhaus booking',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Launcher(loginStatus),
    );
  }
}

class LoadingWidget extends StatelessWidget {
  final String text;
  const LoadingWidget(this.text);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("waiting")
      ),
      body: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              Text(text)
            ]
          )
        ]
      )
    );
  }
}

class Launcher extends StatelessWidget {
  final Future<LoginStatus> loginStatus;
  const Launcher(this.loginStatus);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: loginStatus,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          if (snapshot.data == LoginStatus.loggedIn) {
            WidgetsBinding.instance!.addPostFrameCallback((_) {
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => BookingPage()));
            });
            return Container();
          } else {
            WidgetsBinding.instance!.addPostFrameCallback((_) {
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => LoginPage()));
            });
            return Container();
          }
        } else {
          return LoadingWidget("checking login status");
        }
      }
    );
  }
}

enum BookingPageState {
  loadingSlots,
  haveSlots,
}

class BookingPage extends StatefulWidget {
  @override
  _BookingPageState createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  CancelableOperation? slotsFutureCanceler;
  Future<Null>? slotsFuture;
  late List<dynamic> slots;
  late BookingPageState state;
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    state = BookingPageState.loadingSlots;
  }

  @override
  Widget build(BuildContext context) {
    var currentDate = DateTime.now();

    if (slotsFuture == null) {
      slotsFutureCanceler = CancelableOperation.fromFuture(api.slots(DateTime.now()));
      slotsFuture = slotsFutureCanceler!.value.then<Null>((s) {
          setState(() {
              slots = s;
              state = BookingPageState.haveSlots;
          });
      });
    }

    var slotsWidget;
    if (state == BookingPageState.loadingSlots) {
      slotsWidget = CircularProgressIndicator();
    } else {
      slotsWidget = SlotsWidget(slots);
    }

    var initialDate = currentDate;
    if (selectedDate != null) {
      initialDate = selectedDate!;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Booking page"),
        actions: [
          IconButton(icon: Icon(Icons.edit), onPressed: () {
              WidgetsBinding.instance!.addPostFrameCallback((_) {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                        return FutureBuilder<Map<String, dynamic>>(
                          future: api.userInfo(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return ModifyUser(snapshot.data!);
                            } else {
                              return LoadingWidget("reading user data");
                            }
                          }
                        );
                      }));
              });
          }),
          IconButton(icon: Icon(Icons.exit_to_app), onPressed: () {
              api.logout().then((_) {
                  WidgetsBinding.instance!.addPostFrameCallback((_) {
                      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => Launcher(api.loginStatus())));
                  });
              });
          })
        ],
      ),
      body: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: centimeterToPixel(context, pageWidthCm)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                CalendarDatePicker(
                  initialDate: initialDate,
                  firstDate: currentDate,
                  lastDate: currentDate.add(new Duration(days: 365)),
                  onDateChanged: (date) {
                    setState(() {
                        state = BookingPageState.loadingSlots;
                        selectedDate = date;
                        slotsFutureCanceler?.cancel();
                        slotsFutureCanceler = CancelableOperation.fromFuture(api.slots(date));
                        slotsFuture = slotsFutureCanceler!.value.then<Null>((s) {
                            setState(() {
                                slots = s;
                                state = BookingPageState.haveSlots;
                            });
                        });
                    });
                  },
                  currentDate: currentDate
                ),
                SizedBox(height: 10),
                slotsWidget
              ]
            )
          )
        ]
      )
    );
  }
}

enum ModifyUserState {
  editing,
  saving,
}

class ModifyUser extends StatefulWidget {
  final Map<String, dynamic> previousSettings;

  const ModifyUser(this.previousSettings);

  @override
  _ModifyUserState createState() => _ModifyUserState();
}

class _ModifyUserState extends State<ModifyUser> {
  late UserSettingsController settingsController;
  late ModifyUserState state;


  @override
  void initState() {
    super.initState();
    settingsController = UserSettingsController();
    for (var controller in settingsController.controllers.entries) {
      controller.value.text = widget.previousSettings[controller.key];
    }
    state = ModifyUserState.editing;
  }

  @override
  Widget build(BuildContext context) {
    var button;
    if (state == ModifyUserState.editing) {
      button = RaisedButton(
        child: Text("Save"),
        onPressed: () {
          setState(() => state = ModifyUserState.saving);
          api.modifyUser(settingsController.info()).then((_) {
              WidgetsBinding.instance!.addPostFrameCallback((_) {
                  Navigator.of(context).pop();
              });
            }
          );
        }
      );
    } else {
      button = RaisedButton.icon(
        icon: SizedBox(height: 20, width: 20, child: CircularProgressIndicator()),
        label: Text("saving"),
        onPressed: null
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text("Modify user")),
      body: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SingleChildScrollView(
            child: Container(
              constraints: BoxConstraints(maxWidth: centimeterToPixel(context, pageWidthCm)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  UserSettings(settingsController, readOnly: state == ModifyUserState.saving),
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: button
                  )
                ]
              )
            )
          )
        ]
      )
    );
  }
}

class SlotsWidget extends StatefulWidget {
  final List<dynamic> slots;

  const SlotsWidget(this.slots);

  @override
  _SlotsWidgetState createState() => _SlotsWidgetState();
}

class _SlotsWidgetState extends State<SlotsWidget> {
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child:
        SingleChildScrollView(
          child: Column(
            children: [
              for (var slot in widget.slots)
              SlotTile(slot)
            ]
          )
        )
    );
  }
}


enum SlotTileState {
  bookable,
  booking,
  booked,
  error,
}

class SlotTile extends StatefulWidget {
  final slot;

  const SlotTile(this.slot);

  @override
  _SlotTileState createState() => _SlotTileState();
}

class _SlotTileState extends State<SlotTile> {
  late SlotTileState state;

  @override
  void initState() {
    super.initState();
    state = SlotTileState.bookable;
  }

  @override
  Widget build(BuildContext context) {
    var text = "Error";
    var onPressed;
    var button = RaisedButton.icon(
      icon: Icon(Icons.error, color: Colors.red),
      label: Text(text),
      onPressed: null
    );


    if (state == SlotTileState.bookable) {
      text = "Book";
      onPressed = () {
        setState(() => state = SlotTileState.booking);
        api.bookSlot(widget.slot[2]).then((RequestStatus status) {
            setState(() {
                if (status == RequestStatus.ok) {
                  state = SlotTileState.booked;
                } else {
                  state = SlotTileState.error;
                }
            });
        });
      };

      button = RaisedButton(
        child: Text(text),
        onPressed: onPressed
      );
    }

    if (state == SlotTileState.booking) {
      text = "Booking";
      button = RaisedButton.icon(
        icon: SizedBox(width: 20, height: 20, child: CircularProgressIndicator()),
        label: Text(text),
        onPressed: null
      );
    }

    if (state == SlotTileState.booked) {
      text = "Booked";
      button = RaisedButton.icon(
        icon: Icon(Icons.done, color: Colors.green),
        label: Text(text),
        onPressed: null
      );
    }

    return ListTile(
      title: Text(widget.slot[0]),
      subtitle: Text(widget.slot[1]),
      trailing: button
    );
  }
}

enum LoginState {
  fillingOut,
  tryingLogin,
}


class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool failedPreviously = false;
  LoginState loginState = LoginState.fillingOut;


  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var readOnly = loginState == LoginState.tryingLogin;
    var onPressed;
    if (!readOnly) {
      onPressed = () {
        setState(() {
            loginState = LoginState.tryingLogin;
            api.login(_usernameController.text, _passwordController.text).then((RequestStatus status) {
                if (status == RequestStatus.ok) {
                  WidgetsBinding.instance!.addPostFrameCallback((_) {
                      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => BookingPage()));
                  });
                } else {
                  setState(() {
                      failedPreviously = true;
                      loginState = LoginState.fillingOut;
                  });
                }
            });
        });
      };
    }

    var button;
    if (readOnly){
      button = RaisedButton.icon(
        icon: SizedBox(height: 20, width: 20, child: CircularProgressIndicator()),
        label: Text("Login"),
        onPressed: null
      );
    } else {
      button = RaisedButton(
        child: Text("Login"),
        onPressed: onPressed,
      );
    }

    var createButton;
    if (readOnly) {
      createButton = RaisedButton(child: Text("Create User"), onPressed: null);
    } else {
      createButton = RaisedButton(child: Text("Create User"), onPressed: () {
          WidgetsBinding.instance!.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => CreateUserPage()));
          });
        }
      );
    }

    var errorText;
    if (failedPreviously) {
      errorText = "wrong username or password";
    }

    return Scaffold(
      appBar: AppBar(title: Text("Login")),
      body: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: centimeterToPixel(context, pageWidthCm)),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Book your Boulderhaus Heidelberg Slot with an single click (after creating an account)"),
                TextField(controller: _usernameController, readOnly: readOnly, onChanged: (_) => setState(() => failedPreviously = false), decoration: InputDecoration(filled: true, labelText: "Username", errorText: errorText)),
                SizedBox(height: 10),
                TextField(controller: _passwordController, readOnly: readOnly, onSubmitted: (_) => onPressed(), onChanged: (_) => setState(() => failedPreviously = false), obscureText: true, decoration: InputDecoration(filled: true, labelText: "Password")),
                SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: button
                ),
                SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: createButton
                ),
              ]
            )
          )
        ]
      )
    );
  }
}

enum CreateUserState {
  fillingOut,
  creatingUser,
}

class CreateUserPage extends StatefulWidget {
  @override
  _CreateUserPageState createState() => _CreateUserPageState();
}


class _CreateUserPageState extends State<CreateUserPage> {
  late UserSettingsController settingsController;
  late CreateUserState createUserState;
  late bool failedPreviously;
  late bool haveSubscription;
  late bool haveSubscriptionUnchecked;

  @override
  void initState() {
    super.initState();
    settingsController = UserSettingsController(withUsername: true);
    createUserState = CreateUserState.fillingOut;
    failedPreviously = false;
    haveSubscription = false;
    haveSubscriptionUnchecked = false;
  }

  @override
  void dispose() {
    settingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var creatingUser = createUserState == CreateUserState.creatingUser;
    var subscriptionCheckbox;
    var color;
    var button;

    if (creatingUser) {
      button = RaisedButton.icon(
        icon: SizedBox(height: 20, width: 20, child: CircularProgressIndicator()),
        label: Text("Create user"),
        onPressed: null
      );

      subscriptionCheckbox = Checkbox(value: haveSubscription, onChanged: null);
    } else {
      button = RaisedButton(child: Text("Create user"), onPressed: () {
          if (!haveSubscription) {
            setState(() => haveSubscriptionUnchecked = true);
            return;
          }

          setState(() => createUserState = CreateUserState.creatingUser);

          var info = settingsController.info();
          api.createUser(info["username"], info["password"], info).then((RequestStatus status) {
              if (status == RequestStatus.ok) {
                WidgetsBinding.instance!.addPostFrameCallback((_) {
                    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => BookingPage()));
                });
              } else {
                setState(() {
                    createUserState = CreateUserState.fillingOut;
                    failedPreviously = true;
                });
              }
          });
      });

      if (haveSubscriptionUnchecked) {
        color = Color(0xffe53935);
      }

      subscriptionCheckbox = Checkbox(onChanged: (value) {
          setState(() {
              haveSubscription = value!;
              haveSubscriptionUnchecked = false;
          });
        },
        value: haveSubscription
      );

      subscriptionCheckbox = Theme(
        data: ThemeData(unselectedWidgetColor: color),
        child: subscriptionCheckbox
      );
    }

    subscriptionCheckbox = Row(
      children: [
        subscriptionCheckbox,
        Text("I have a subscription", style: TextStyle(color: color))
      ]
    );


    var errorText;
    if (failedPreviously) {
      errorText = "creating user failed, maybe the username is already taken?";
    }

    return Scaffold(
      appBar: AppBar(title: Text("Create user")),
      body: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SingleChildScrollView(
            child: Container(
              constraints: BoxConstraints(maxWidth: centimeterToPixel(context, pageWidthCm)),
              child:
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  UserSettings(settingsController, readOnly: creatingUser, onAnyChanged: () => setState(() => failedPreviously = false)),
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: subscriptionCheckbox,
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: button
                  )
                ]
              )
            )
          )
        ]
      )
    );
  }
}

class UserSettingsController {
  List<String> settings = ["firstname", "lastname", "street", "postal_code", "city", "email", "phone", "birthdate", "customer_no"];
  bool? withUsername;
  Map<String, TextEditingController> controllers = Map<String, TextEditingController>();

  UserSettingsController({this.withUsername}) {
    if (withUsername == null) {
      withUsername = false;
    }

    if (withUsername!) {
      settings = ["username", "password", ...settings];
    }

    for (var setting in settings) {
      controllers[setting] = TextEditingController();
    }
  }

  void dispose() {
    for (var setting in settings) {
      controllers[setting]!.dispose();
    }
  }

  Map<String, String> info() {
    var theInfo = Map<String, String>();

    for (var setting in settings) {
      theInfo[setting] = controllers[setting]!.text;
    }

    return theInfo;
  }
}

class UserSettings extends StatefulWidget {
  final UserSettingsController controller;
  var readOnly;
  final onAnyChanged;

  UserSettings(this.controller, {this.readOnly, this.onAnyChanged}) {
    if (readOnly == null) {
      readOnly = false;
    }
  }

  @override
  _UserSettingsState createState() => _UserSettingsState();
}

class _UserSettingsState extends State<UserSettings> {
  @override
  Widget build(BuildContext context) {
    String beautifyName(String name) {
      name = name[0].toUpperCase() + name.substring(1);
      name = name.replaceAll('_', ' ');
      return name;
    }

    return Container(
            constraints: BoxConstraints(maxWidth: centimeterToPixel(context, pageWidthCm)),
            child: Column(
              children: [
                for (var setting in widget.controller.settings)
                ...[
                  TextField(controller: widget.controller.controllers[setting], obscureText: setting == "password", readOnly: widget.readOnly, onChanged: (_) => widget.onAnyChanged(), decoration: InputDecoration(filled: true, labelText: beautifyName(setting))),
                  SizedBox(height: 10)
                ]
              ]
            )
          );
  }
}
