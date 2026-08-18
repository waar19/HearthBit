enum PrivateMessageSendDisposition { sent, queued, failed }

class PrivateMessageSendResult {
  const PrivateMessageSendResult._(this.disposition, {this.error});

  const PrivateMessageSendResult.sent()
    : this._(PrivateMessageSendDisposition.sent);

  const PrivateMessageSendResult.queued()
    : this._(PrivateMessageSendDisposition.queued);

  const PrivateMessageSendResult.failed(String error)
    : this._(PrivateMessageSendDisposition.failed, error: error);

  final PrivateMessageSendDisposition disposition;
  final String? error;

  bool get accepted => disposition != PrivateMessageSendDisposition.failed;
}
