class UserModel {
  final String username;
  final String email;
  final String subscriptionStatus; // "None", "Trialing", "Active"
  final DateTime? trialEndDate;
  final DateTime? subscriptionEndDate;

  UserModel({
    required this.username,
    required this.email,
    required this.subscriptionStatus,
    this.trialEndDate,
    this.subscriptionEndDate,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      subscriptionStatus: json['subscriptionStatus'] ?? 'None',
      trialEndDate: json['trialEndDate'] != null 
          ? DateTime.parse(json['trialEndDate']) 
          : null,
      subscriptionEndDate: json['subscriptionEndDate'] != null 
          ? DateTime.parse(json['subscriptionEndDate']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'email': email,
    'subscriptionStatus': subscriptionStatus,
    'trialEndDate': trialEndDate?.toIso8601String(),
    'subscriptionEndDate': subscriptionEndDate?.toIso8601String(),
  };
}