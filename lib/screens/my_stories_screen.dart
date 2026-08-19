import 'package:flutter/material.dart';
import '../models/story_model.dart';
import 'story_viewer_screen.dart';

class MyStoriesScreen extends StatelessWidget {
  final UserStories myStories;

  const MyStoriesScreen({super.key, required this.myStories});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0F3460);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Status saya'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        itemCount: myStories.stories.length,
        itemBuilder: (context, index) {
          final story = myStories.stories[index];
          
          // Format date/time
          final hourStr = story.createdAt.hour.toString().padLeft(2, '0');
          final minuteStr = story.createdAt.minute.toString().padLeft(2, '0');
          final timeStr = '$hourStr.$minuteStr';
          final privacyText = story.privacyType.replaceAll('_', ' ').replaceFirst(story.privacyType[0], story.privacyType[0].toUpperCase());
          
          Widget leadingWidget;
          if (story.contentType == 'text') {
            leadingWidget = Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: story.backgroundColor != null && story.backgroundColor!.startsWith('#')
                    ? Color(int.parse(story.backgroundColor!.substring(1), radix: 16) + 0xFF000000)
                    : Colors.grey,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  story.textContent?.substring(0, 1).toUpperCase() ?? 'S',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            );
          } else {
            // Can add image thumbnail here later if mediaType is image
            leadingWidget = Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.image, color: Colors.white),
            );
          }

          return ListTile(
            leading: leadingWidget,
            title: Text('${story.viewers.length}x dilihat', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Hari ini $timeStr • $privacyText'),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'teruskan') {
                  // Forward logic
                } else if (value == 'bagikan') {
                  // Share logic
                } else if (value == 'hapus') {
                  // Delete logic
                }
              },
              itemBuilder: (BuildContext context) {
                return const [
                  PopupMenuItem(value: 'teruskan', child: Text('Teruskan')),
                  PopupMenuItem(value: 'bagikan', child: Text('Bagikan')),
                  PopupMenuItem(value: 'hapus', child: Text('Hapus')),
                ];
              },
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryViewerScreen(userStories: myStories),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
