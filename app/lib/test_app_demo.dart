import 'package:flutter/material.dart';

void main() => runApp(const TestAppDemo());

class TestAppDemo extends StatelessWidget {
  const TestAppDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Test App',
      home: TestAppDemoPage(),
    );
  }
}

class TestAppDemoPage extends StatefulWidget {
  const TestAppDemoPage({super.key});

  @override
  State<TestAppDemoPage> createState() => _TestAppDemoPageState();
}

class _TestAppDemoPageState extends State<TestAppDemoPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test App')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Zählerstand'),
            Text(_count.toString(), key: const Key('counter-value')),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Verringern',
                  onPressed: () {
                    if (_count > 0) setState(() => _count--);
                  },
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: 'Erhöhen',
                  onPressed: () => setState(() => _count++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
