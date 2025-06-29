import React, { useEffect, useState } from 'react';
import {
  SafeAreaView,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  View,
  Alert,
  Platform,
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import NetInfo from '@react-native-community/netinfo';
import PushNotification from 'react-native-push-notification';
import CodePush from 'react-native-code-push';
import { Linking } from 'react-native';
import TouchID from 'react-native-touch-id';

// Import custom services
import OfflineService from './src/services/OfflineService';
import PerformanceService from './src/services/PerformanceService';
import AuthService from './src/services/AuthService';
import DeepLinkingService from './src/services/DeepLinkingService';

const App = () => {
  const [isOnline, setIsOnline] = useState(true);
  const [updateProgress, setUpdateProgress] = useState(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  useEffect(() => {
    initializeApp();
  }, []);

  const initializeApp = async () => {
    try {
      // Initialize performance monitoring
      PerformanceService.initialize();
      
      // Initialize offline service
      await OfflineService.initialize();
      
      // Setup network monitoring
      setupNetworkMonitoring();
      
      // Setup push notifications
      setupPushNotifications();
      
      // Setup deep linking
      setupDeepLinking();
      
      // Check for CodePush updates
      checkForUpdates();
      
      // Check authentication status
      checkAuthenticationStatus();
      
    } catch (error) {
      console.error('App initialization error:', error);
      PerformanceService.recordError('app_initialization_error', error);
    }
  };

  const setupNetworkMonitoring = () => {
    const unsubscribe = NetInfo.addEventListener(state => {
      setIsOnline(state.isConnected);
      
      if (state.isConnected) {
        // Sync offline data when back online
        OfflineService.syncPendingData();
      }
      
      // Record network status
      PerformanceService.recordNetworkStatus(state);
    });

    return unsubscribe;
  };

  const setupPushNotifications = () => {
    PushNotification.configure({
      onRegister: function(token) {
        console.log('Push notification token:', token);
        // Send token to server
        AuthService.updatePushToken(token.token);
      },

      onNotification: function(notification) {
        console.log('Push notification received:', notification);
        
        // Handle notification based on type
        if (notification.userInteraction) {
          // User tapped on notification
          handleNotificationTap(notification);
        }
        
        // Record notification metrics
        PerformanceService.recordNotification(notification);
      },

      onAction: function(notification) {
        console.log('Notification action:', notification.action);
      },

      onRegistrationError: function(err) {
        console.error('Push notification registration error:', err);
        PerformanceService.recordError('push_registration_error', err);
      },

      permissions: {
        alert: true,
        badge: true,
        sound: true,
      },

      popInitialNotification: true,
      requestPermissions: Platform.OS === 'ios',
    });
  };

  const setupDeepLinking = () => {
    // Handle initial URL if app was opened via deep link
    Linking.getInitialURL().then(url => {
      if (url) {
        DeepLinkingService.handleDeepLink(url);
      }
    });

    // Listen for deep links while app is running
    const linkingListener = Linking.addEventListener('url', ({ url }) => {
      DeepLinkingService.handleDeepLink(url);
    });

    return () => {
      linkingListener?.remove();
    };
  };

  const checkForUpdates = () => {
    CodePush.sync(
      {
        updateDialog: {
          title: 'Update Available',
          description: 'A new version of the app is available. Would you like to update?',
          mandatoryUpdateMessage: 'An update is required to continue using the app.',
          mandatoryContinueButtonLabel: 'Continue',
          optionalIgnoreButtonLabel: 'Later',
          optionalInstallButtonLabel: 'Install',
        },
        installMode: CodePush.InstallMode.IMMEDIATE,
      },
      (status) => {
        switch (status) {
          case CodePush.SyncStatus.DOWNLOADING_PACKAGE:
            console.log('Downloading update...');
            break;
          case CodePush.SyncStatus.INSTALLING_UPDATE:
            console.log('Installing update...');
            break;
          case CodePush.SyncStatus.UP_TO_DATE:
            console.log('App is up to date');
            break;
          case CodePush.SyncStatus.UPDATE_INSTALLED:
            console.log('Update installed successfully');
            break;
        }
      },
      ({ receivedBytes, totalBytes }) => {
        const progress = (receivedBytes / totalBytes) * 100;
        setUpdateProgress(progress);
      }
    );
  };

  const checkAuthenticationStatus = async () => {
    try {
      const token = await AsyncStorage.getItem('authToken');
      if (token) {
        const isValid = await AuthService.validateToken(token);
        setIsAuthenticated(isValid);
      }
    } catch (error) {
      console.error('Authentication check error:', error);
    }
  };

  const handleBiometricAuth = async () => {
    try {
      const biometryType = await TouchID.isSupported();
      if (biometryType) {
        const isAuthenticated = await TouchID.authenticate('Authenticate to access the app', {
          title: 'Authentication Required',
          subtitle: 'Use your biometric to authenticate',
          description: 'This app uses biometric authentication to protect your data',
          fallbackLabel: 'Use Passcode',
          cancelLabel: 'Cancel',
        });
        
        if (isAuthenticated) {
          setIsAuthenticated(true);
          PerformanceService.recordEvent('biometric_auth_success');
        }
      }
    } catch (error) {
      console.error('Biometric authentication error:', error);
      PerformanceService.recordError('biometric_auth_error', error);
      
      // Fallback to regular authentication
      Alert.alert(
        'Authentication Failed',
        'Biometric authentication failed. Please use your passcode.',
        [{ text: 'OK' }]
      );
    }
  };

  const handleNotificationTap = (notification) => {
    // Navigate based on notification data
    if (notification.data?.screen) {
      // Navigate to specific screen
      console.log('Navigate to:', notification.data.screen);
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      
      <ScrollView contentInsetAdjustmentBehavior="automatic" style={styles.scrollView}>
        <View style={styles.header}>
          <Text style={styles.title}>Nexus V3 Mobile</Text>
          <Text style={styles.subtitle}>Enterprise React Native Enhancement</Text>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Connection Status</Text>
          <View style={[styles.statusIndicator, { backgroundColor: isOnline ? '#4CAF50' : '#F44336' }]}>
            <Text style={styles.statusText}>
              {isOnline ? 'Online' : 'Offline'}
            </Text>
          </View>
        </View>

        {updateProgress && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Update Progress</Text>
            <View style={styles.progressBar}>
              <View style={[styles.progressFill, { width: `${updateProgress}%` }]} />
            </View>
            <Text style={styles.progressText}>{Math.round(updateProgress)}%</Text>
          </View>
        )}

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Features</Text>
          <View style={styles.featureList}>
            <Text style={styles.featureItem}>✅ Over-the-Air Updates (CodePush)</Text>
            <Text style={styles.featureItem}>✅ Push Notifications</Text>
            <Text style={styles.featureItem}>✅ Offline-First Architecture</Text>
            <Text style={styles.featureItem}>✅ Deep Linking & Universal Links</Text>
            <Text style={styles.featureItem}>✅ Biometric Authentication</Text>
            <Text style={styles.featureItem}>✅ Performance Monitoring</Text>
            <Text style={styles.featureItem}>✅ Native Module Integration</Text>
          </View>
        </View>

        {!isAuthenticated && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Authentication Required</Text>
            <TouchableOpacity style={styles.authButton} onPress={handleBiometricAuth}>
              <Text style={styles.authButtonText}>Authenticate with Biometrics</Text>
            </TouchableOpacity>
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
  scrollView: {
    flex: 1,
  },
  header: {
    padding: 20,
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 5,
  },
  subtitle: {
    fontSize: 16,
    color: '#666666',
  },
  section: {
    padding: 20,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333333',
    marginBottom: 10,
  },
  statusIndicator: {
    padding: 10,
    borderRadius: 5,
    alignItems: 'center',
  },
  statusText: {
    color: '#ffffff',
    fontWeight: '600',
  },
  progressBar: {
    height: 10,
    backgroundColor: '#e0e0e0',
    borderRadius: 5,
    overflow: 'hidden',
    marginBottom: 5,
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#4CAF50',
  },
  progressText: {
    textAlign: 'center',
    color: '#666666',
  },
  featureList: {
    marginTop: 10,
  },
  featureItem: {
    fontSize: 16,
    color: '#333333',
    marginBottom: 5,
  },
  authButton: {
    backgroundColor: '#2196F3',
    padding: 15,
    borderRadius: 5,
    alignItems: 'center',
    marginTop: 10,
  },
  authButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '600',
  },
});

// Configure CodePush
const codePushOptions = {
  checkFrequency: CodePush.CheckFrequency.ON_APP_RESUME,
  installMode: CodePush.InstallMode.ON_NEXT_RESUME,
};

export default CodePush(codePushOptions)(App);
