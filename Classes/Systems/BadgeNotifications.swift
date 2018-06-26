//
//  BadgeNotifications.swift
//  Freetime
//
//  Created by Ryan Nystrom on 8/12/17.
//  Copyright © 2017 Ryan Nystrom. All rights reserved.
//

import UIKit
import UserNotifications
import GitHubAPI
import GitHubSession

final class BadgeNotifications {

    private static let userKey = "com.freetime.BadgeNotifications.user-enabled"
    private static let countWhenDisabledKey = "com.freetime.BadgeNotifications.count-when-disabled"

    static var isEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            return defaults.bool(forKey: userKey)
        }
        set {
            let defaults = UserDefaults.standard
            let application = UIApplication.shared
            if newValue == false {
                defaults.set(application.applicationIconBadgeNumber, forKey: countWhenDisabledKey)
                application.applicationIconBadgeNumber = 0
            } else {
                application.applicationIconBadgeNumber = defaults.integer(forKey: countWhenDisabledKey)
            }
            defaults.set(newValue, forKey: BadgeNotifications.userKey)
        }
    }

    enum State {
        case initial
        case denied
        case disabled
        case enabled
    }

    static func check(callback: @escaping (State) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    callback(.initial)
                case .denied:
                    callback(.denied)
                case .provisional: fallthrough
                case .authorized:
                    callback(isEnabled ? .enabled : .disabled)
                }
            }
        }
    }

    static func configure(application: UIApplication = UIApplication.shared, permissionHandler: ((Bool) -> Void)? = nil) {
        if isEnabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.badge], completionHandler: { (granted, _) in
                permissionHandler?(granted)
            })
            application.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalMinimum)
        } else {
            application.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
        }
    }

    private var backgroundClient: GithubClient? = nil
    func fetch(application: UIApplication, handler: @escaping (UIBackgroundFetchResult) -> Void) {
        let manager = GitHubSessionManager()
        guard let session = manager.focusedUserSession,
            BadgeNotifications.isEnabled
            else { return }

        backgroundClient = newGithubClient(userSession: session)
        backgroundClient?.client.send(V3NotificationRequest(all: false)) { result in
            switch result {
            case .success(let response):
                let changes = BadgeNotifications.update(application: application, count: response.data.count)
                handler(changes ? .newData : .noData)
            case .failure:
                handler(.failed)
            }
        }
    }

    @discardableResult
    static func update(application: UIApplication = UIApplication.shared, count: Int) -> Bool {
        let enabledCount = isEnabled ? count : 0
        let changed = application.applicationIconBadgeNumber != enabledCount
        application.applicationIconBadgeNumber = enabledCount
        return changed
    }

}
