import 'package:api_client/api_client.dart';

class HeadlineController extends Endpoint {
  HeadlineController()
    : super(
        path: '/top-headlines',
        responseDecoder: (data) {
          // print()
        },
      );
}
