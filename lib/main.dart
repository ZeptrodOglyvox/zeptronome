import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:math';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:wakelock/wakelock.dart';
void main() {runApp(MyApp());
}

var appStyle = {
  'border_radius': BorderRadius.all(Radius.circular(10)),
};

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIOverlays([SystemUiOverlay.bottom]);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    Wakelock.enable();
    return MaterialApp(
      title: "The Zeptronome",
      theme: ThemeData(
        primaryColor: Colors.pink[400],
        accentColor: Colors.pink[600],
        disabledColor: Colors.pink,
        scaffoldBackgroundColor: Colors.pink[400]
      ),
      home: Scaffold(
        body: Container(
          padding: EdgeInsets.symmetric(vertical: 35.0, horizontal: 25),
          child: Column(
            children: <Widget>[
              Container(
                margin: EdgeInsets.only(top: 15, bottom: 35),
                child: Text(
                    'THE ZEPTRONOME',
                    style: TextStyle(fontSize: 30, color: Colors.white)
                ),
              ),
              Expanded(child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  MetronomeSection(),
                  CounterSection(),
                  RecorderSection()
                ],
              ))
            ],
          ),
        )
      )
    );
  }
}

class AppButton extends StatelessWidget {
  final icon;
  final onPressed;
  final disabled;
  AppButton({this.icon, this.onPressed, this.disabled = false}): super();

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Ink(
          width: 85,
          height: 85,
          decoration: BoxDecoration(
              color: disabled ?
                Theme.of(context).disabledColor :
                Theme.of(context).accentColor,
              borderRadius: appStyle['border_radius']
          ),
          child: IconButton(
            icon: Icon(icon, size: 50),
            color: Theme.of(context).primaryColor,
            disabledColor: Theme.of(context).primaryColor,
            onPressed: disabled ? null : onPressed,
          ),
        )
    );
  }
}

class MetronomeSection extends StatefulWidget {
  @override
  _MetronomeSectionState createState() => _MetronomeSectionState();
}

class _MetronomeSectionState extends State<MetronomeSection> {
  // tempo is the actual value used.
  // tempoBuffer is a double that gathers up all the deltas from the events
  // so that they don't get lost when you do something like
  // tempo += (dx * 0.1).toInt()
  int tempo = 120;
  double tempoBuffer = 120.0;
  Duration duration = new Duration(
      milliseconds: 1000 * 60 ~/ 120
  );

  IconData icon = Icons.play_arrow;
  bool playing = false;

  FlutterSoundPlayer player;
  FlutterSoundPlayer session;
  Uint8List buffer;
  StreamSubscription stream;

  _MetronomeSectionState(): super() {
    player = FlutterSoundPlayer();
    rootBundle.load('./sounds/metronome-long.wav').then(
        (bytedata) => buffer = bytedata.buffer.asUint8List()
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$tempo BPM',
              style: TextStyle(
                fontSize: 50,
                fontWeight: FontWeight.w400,
                color: Colors.white
              )
            ),
            AppButton(icon: icon, onPressed: () async {
              setState(() {
                playing = !playing;
                icon = playing ? Icons.pause : Icons.play_arrow;
              });

              if(playing) {
                session = await player.openAudioSession();
                session.startPlayer(fromDataBuffer: buffer, whenFinished: (){});
                stream = Stream.periodic(duration).listen((v) {
                 session.seekToPlayer(Duration(milliseconds: 0));
                });
              } else {
                await session.stopPlayer();
                stream.cancel();
                session.closeAudioSession();
              }
            })
          ],
        ),
        GestureDetector(
          onHorizontalDragUpdate: (DragUpdateDetails details) async {
            setState(() {
              tempoBuffer =
                  min(max(tempoBuffer + details.delta.dx * 0.15,50),300);
              tempo = tempoBuffer.toInt();
              duration = new Duration(
                  milliseconds: 1000 * 60 ~/ tempo
              );
            });
          },
          onHorizontalDragEnd: (details) async {
            if(playing) {
              await session.stopPlayer();
              stream.cancel();

              session.startPlayer(fromDataBuffer: buffer, whenFinished: (){});
              stream = Stream.periodic(duration).listen((v) {
                session.seekToPlayer(Duration(milliseconds: 0));
              });
            }
          },
          child: Container(
            margin: EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
                color: Theme.of(context).accentColor,
                borderRadius: appStyle['border_radius'],
            ),
            width: double.infinity,
            height: 60,
          ),
        )
      ],
    );
  }
}

class CounterSection extends StatefulWidget {
  @override
  _CounterSectionState createState() => _CounterSectionState();
}

class _CounterSectionState extends State<CounterSection> {
  int count = 0;
  final max = 1000;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => count = count + 1 > max ? max : count + 1);
      },
      onLongPress: () {
        setState(() => count = 0);
      },
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(vertical: 45),
        decoration: BoxDecoration(
            color: Theme.of(context).accentColor,
            borderRadius: appStyle['border_radius']
        ),
        child: Text(
          '$count',
          style: TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.w400,
              color: Colors.white
          ),
        )
      ),
    );
  }
}

class RecorderSection extends StatefulWidget {
  @override
  _RecorderSectionState createState() => _RecorderSectionState();
}

class _RecorderSectionState extends State<RecorderSection> {
  bool recording = false;
  bool playing = false;
  bool fileAvailable = false;

  final recorder = FlutterSoundRecorder();
  final player = FlutterSoundPlayer();
  FlutterSoundPlayer playerSession;
  FlutterSoundRecorder recorderSession; //TODO: delete all the initial instances, just use the sessions.
  File outfile;

  _RecorderSectionState(): super() {
    getTemporaryDirectory().then((tempDir){
      outfile = File('${tempDir.path}/zeptro-sound-tmp.aac');
      // print(outfile.path);
    });
  }

  startRecording() async {
    recorderSession = await recorder.openAudioSession();
    PermissionStatus status = await Permission.microphone.request();
    if (status != PermissionStatus.granted)
      throw RecordingPermissionException("Microphone permission not granted");
    await recorder.startRecorder(toFile: outfile.path, codec: Codec.aacADTS,);
  }

  stopRecording() async {
    await recorderSession.stopRecorder();
    await recorderSession.closeAudioSession();
    // print('stopped recording.');
  }

  startPlaying() async {
    playerSession = await player.openAudioSession();
    await playerSession.startPlayer(
        fromURI: outfile.path,
        whenFinished: () async {
          await playerSession.closeAudioSession();
          setState(() { playing = false; });
        });
  }

  stopPlaying() async {
    await playerSession.stopPlayer();
    await playerSession.closeAudioSession();
  }

  deleteFile() async {
    try {
      await outfile.delete();
    } on FileSystemException {
      print('Error when trying to delete the outfile.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AppButton(
          icon: playing ? Icons.pause : Icons.play_arrow,
          disabled: !fileAvailable,
          onPressed: () async {
            if (fileAvailable) {
              setState(() => playing = !playing);
              if(playing) {
                if (recording) {
                  await stopRecording();
                  setState(() => recording = false);
                }
                await startPlaying();
              } else await stopPlaying();
            }
          }
        ),
        AppButton(icon: recording ? Icons.stop : Icons.circle, onPressed: () async {
          setState(() => recording = !recording);
          if(recording) {
            if (playing) {
              await stopPlaying();
              setState(() => playing = false);
            }
            await startRecording();
          } else {
            await stopRecording();
            setState(() => fileAvailable = true);
          }
        }),
        AppButton(icon: Icons.delete, onPressed: () async {
          if (fileAvailable) {
            if (playing) {
              await stopPlaying();
              setState(() => playing = false);
            }
            await deleteFile();
            setState(() => fileAvailable = false);
          }
        }),
      ],
    );
  }
}