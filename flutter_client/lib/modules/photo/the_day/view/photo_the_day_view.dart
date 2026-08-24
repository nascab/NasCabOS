import 'package:flutter/material.dart';

import '../../timeline/view/pc_photo_timeline.dart';

class PhotoTheDayView extends StatelessWidget {
  const PhotoTheDayView({super.key});

  @override
  Widget build(BuildContext context) {
    return const PcPhotoTimelineView(
      key: ValueKey('the_day'),
      listType: 'timeline',
      loadTheDay: true,
    );
  }
}
