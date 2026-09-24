// Section 5 regression coverage (Sell media investigation):
//
//   * `buildMediaUrl` (lib/shared/media/media_url.dart) must never double-
//     prefix an already-absolute R2/CDN URL -- this is the Flutter-side
//     half of the bare-R2-key backend fix: once `_resolve_rel()` on the
//     backend reconstructs a full `https://` URL for a previously-bare R2
//     key, the client must display it as-is, not treat it as a relative
//     Flask path again.
//   * The `content://` vs. `http(s)://` vs. local-file classification used
//     by `GalleryEmbeddedVideoPlayer._init()` in
//     `lib/widgets/in_app_video_screen.dart` to choose between
//     `VideoPlayerController.networkUrl`, `.contentUri`, and `.file` is
//     covered here as a pure-logic mirror of that widget's branching
//     predicates. A real `testWidgets` pump of a `VideoPlayerController`
//     is not exercised (no real platform video decoder in this sandboxed
//     `flutter_test` environment -- the same constraint documented in
//     `test/listing_network_image_local_file_test.dart` for
//     `Image.file`/`Image.memory`); this instead proves the three-way
//     decision itself is correct for every URL shape the Sell flow and
//     published-listing playback can produce.
import 'package:car_listing_app/shared/media/media_url.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the exact classification in
/// `lib/widgets/in_app_video_screen.dart::GalleryEmbeddedVideoPlayer._init()`:
///
/// ```dart
/// final bool isNetwork = url.startsWith('http://') || url.startsWith('https://');
/// final bool isContentUri = url.startsWith('content://');
/// final VideoPlayerController c = isNetwork
///     ? VideoPlayerController.networkUrl(Uri.parse(url))
///     : isContentUri
///         ? VideoPlayerController.contentUri(Uri.parse(url))
///         : VideoPlayerController.file(File(url));
/// ```
enum _VideoControllerKind { network, contentUri, file }

_VideoControllerKind _classifyVideoUrl(String url) {
  final bool isNetwork = url.startsWith('http://') || url.startsWith('https://');
  if (isNetwork) return _VideoControllerKind.network;
  final bool isContentUri = url.startsWith('content://');
  if (isContentUri) return _VideoControllerKind.contentUri;
  return _VideoControllerKind.file;
}

void main() {
  group('buildMediaUrl double-prefix regression', () {
    test('an absolute R2/CDN https:// URL is never double-prefixed', () {
      const r2Url = 'https://cdn.example.com/car_photos/owner1/photo.jpg';
      expect(buildMediaUrl(r2Url), r2Url);
      expect(buildMediaUrl(r2Url), isNot(contains('/static/')));
    });

    test('an absolute http:// URL is also passed through unchanged', () {
      const url = 'http://cdn.example.com/car_videos/clip.mp4';
      expect(buildMediaUrl(url), url);
    });

    test(
      'only a backend-relative /static/ absolute URL gets rewritten onto '
      'the current API base (emulator-reachability rewrite, not a bug)',
      () {
        final rewritten = buildMediaUrl(
          'https://old-host.example.com/static/uploads/car_photos/x.jpg',
        );
        expect(rewritten, contains('/static/uploads/car_photos/x.jpg'));
        expect(rewritten, isNot(contains('old-host.example.com')));
      },
    );
  });

  group(
    'video controller URL classification (mirrors GalleryEmbeddedVideoPlayer._init)',
    () {
      test('a published listing https:// video URL routes to networkUrl', () {
        expect(
          _classifyVideoUrl('https://cdn.example.com/car_videos/clip.mp4'),
          _VideoControllerKind.network,
        );
      });

      test('a published listing http:// video URL also routes to networkUrl', () {
        expect(
          _classifyVideoUrl('http://cdn.example.com/car_videos/clip.mp4'),
          _VideoControllerKind.network,
        );
      });

      test(
        'a Sell-flow content:// picked video routes to contentUri, never '
        'to File() (which cannot resolve content:// on Android)',
        () {
          expect(
            _classifyVideoUrl(
              'content://media/external/video/media/12345',
            ),
            _VideoControllerKind.contentUri,
          );
        },
      );

      test(
        'a real absolute local file path (e.g. a durable copy under app '
        'storage, or a generated thumbnail temp file) still routes to '
        'File() -- the content:// fix must not regress this case',
        () {
          expect(
            _classifyVideoUrl('/data/user/0/com.example.app/files/video.mp4'),
            _VideoControllerKind.file,
          );
        },
      );

      test(
        'a remote https:// video is never accidentally classified as '
        'local File (would crash trying to open a URL as a filesystem path)',
        () {
          expect(
            _classifyVideoUrl('https://cdn.example.com/car_videos/clip.mp4'),
            isNot(_VideoControllerKind.file),
          );
        },
      );

      test(
        'a local content:// video is never accidentally classified as '
        'network (content:// is not a fetchable http(s) URL)',
        () {
          expect(
            _classifyVideoUrl('content://media/external/video/media/1'),
            isNot(_VideoControllerKind.network),
          );
        },
      );
    },
  );
}
