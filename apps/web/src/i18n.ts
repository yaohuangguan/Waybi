/**
 * All interface copy for the web map, the account dashboard and the account
 * forms. Markup carries `data-i18n*` attributes that `applyUiLanguage`
 * resolves, so no element is located by position (`:nth-child`) any more.
 * (The marketing page's editorial copy lives in marketing-copy.ts because it
 * is prerendered at build time and must not ship with the map bundle.)
 */
import type { Language } from './preferences';
export type { Language } from './preferences';

const en = {
  // Document
  title: 'Waybi · Web map', description: 'Independent maps, route planning and New Zealand camera information',
  map: 'Waybi navigation map', home: 'Waybi home', brandAlt: 'Waybi Maps & Navigation',
  // Top bar and GPS
  settings: 'Open settings', profile: 'Account dashboard', locating: 'Locating', gpsUnavailable: 'GPS unavailable',
  enableLocation: 'Use my location', permissionDenied: 'Location blocked', gpsTemporary: 'Location unavailable',
  gpsAccuracyBadge: 'GPS {meters} m',
  permissionHelpIos: 'Location is blocked. On iPhone open Settings → Privacy & Security → Location Services → Safari Websites, choose “While Using the App”, then reload Waybi and tap GPS.',
  permissionHelpIosApp: 'Location is blocked. On iPhone open Settings → Privacy & Security → Location Services, allow location for Safari Websites, then reopen Waybi and tap GPS.',
  permissionHelpAndroid: 'Location is blocked. Tap the site settings icon next to the address bar → Permissions → Location → Allow. Also check that Location is on in Android quick settings, then tap GPS.',
  permissionHelpDesktop: 'Location is blocked. Click the site settings icon next to the address bar, allow Location for waybi.co, then tap GPS again.',
  // Search
  searchPanel: 'Route search', origin: 'Current location · tap to change', originLabel: 'Starting point', destination: 'Search destination',
  useGps: 'Use live location', searchButton: 'Search destination', follow: 'Follow location', recenter: 'Recenter map',
  noGps: 'Waiting for GPS location.', minQuery: 'Type at least 3 characters.', searching: 'Searching…',
  noResults: 'No place found. Try another search.', searchFailed: 'Search failed',
  searchOffline: 'You appear to be offline. Check your connection, then search again.',
  searchBusy: 'Search is busy right now. Try again in {seconds} s.',
  suggestionsOffline: 'Suggestions are unavailable offline. Press Enter to search when you are back online.',
  suggestionsBusy: 'Suggestions are paused for a moment. Press Enter to search.',
  suggestionsLabel: 'Suggestions', suggestionsCount: '{count} suggestions. Use the up and down arrows to choose.',
  retry: 'Retry',
  stopPlaceholder: 'Add a stop', stopLabel: 'Intermediate stop', stopSearch: 'Search stop', removeStop: 'Remove stop {name}',
  currentPlace: 'Current location', guestRecent: 'Recent destinations',
  autocompleteUnavailable: 'Live suggestions need a configured address provider. Press Enter to search.',
  // Route planning
  routeCalculating: 'Calculating route…', destinationFallback: 'Destination', routeError: 'Route unavailable',
  routeFailed: 'Could not calculate route', chooseOrigin: 'Choose a starting point or allow GPS.',
  noRouteAvailable: 'No available route. Change the destination or try again later.',
  routeBusy: 'Route planning is busy. Waybi will retry in {seconds} s.',
  routeOffline: 'You appear to be offline. Waybi will retry the route when it can.',
  stateReady: 'READY TO GO', stateCalculating: 'CALCULATING ROUTE', stateRouteReady: 'ROUTE READY', stateRouteError: 'ROUTE ERROR',
  stateDriving: 'DRIVING MODE', stateGuidance: 'GUIDANCE MODE', stateArrived: 'ARRIVED', stateParkingReached: 'PARKING REACHED',
  initialTitle: 'Plan your next journey', start: 'Start navigation', startShort: 'Start', startTrip: 'Start trip',
  stop: 'End navigation', cancelDestination: 'Clear', clearDestination: 'Clear destination',
  modeDrive: 'Drive', modeTransit: 'Transit', modeWalk: 'Walk', modeBike: 'Bike', travelModes: 'Travel mode',
  recommended: 'recommended', routeAlternatives: 'Route alternatives',
  trafficNormal: 'Normal', trafficSlow: 'Slow', trafficHeavy: 'Heavy traffic',
  trafficUnavailable: 'Live traffic segments are unavailable; route color does not indicate current traffic.',
  trafficAdvisory: 'Traffic advisory', roadAdvisory: 'Road advisory',
  heavySectionsOne: '1 heavy-traffic section ahead', heavySectionsOther: '{count} heavy-traffic sections ahead',
  slowSectionsOne: '1 slow section ahead', slowSectionsOther: '{count} slow sections ahead',
  transitFallback: 'Transit', transitStopsOne: '1 stop', transitStopsOther: '{count} stops',
  addStop: '＋ Add stop', saveRoute: '♡ Save',
  routeSavedAccount: 'Route saved to your account', routeSavedSession: 'Route saved for this session only',
  durationMinutes: '{minutes} min', durationHours: '{hours} h', durationHoursMinutes: '{hours} h {minutes} min',
  // Sheet
  expandSheet: 'Show route details', collapseSheet: 'Hide route details',
  speedLimit: 'Speed limit', nextCamera: 'Next camera', gpsAccuracy: 'GPS accuracy', routeSteps: 'Route steps',
  camerasAlong: 'Cameras on route', distance: 'Distance', arrival: 'Arrival', dataDetails: 'Data details ↗', cameraData: 'Camera data ↗',
  camerasLoading: 'Loading NZTA cameras…', camerasUnavailable: 'Camera data unavailable',
  cameraCount: 'NZTA fixed cameras', cached: 'cached', neverChecked: 'Not checked yet',
  synced: 'Up to date', stale: 'Official source unavailable; using cache', offline: 'Offline cache', seed: 'Initial CSV',
  voiceOn: 'Voice ✓', voiceOff: 'Voice off', lanesOn: 'Lanes ✓', lanesOff: 'Lanes off',
  accountSynced: 'Account synced', guestMode: 'Guest mode', speedLimitBadge: 'LIMIT {value}', speedLimitUnknown: 'LIMIT —',
  currentSpeed: 'Current speed', speedUnit: 'km/h',
  cameraList: 'Camera list', cameraListRoute: 'Cameras on this route', cameraListNearby: 'Cameras near the map centre',
  cameraListEmpty: 'No cameras to list here.', cameraListHint: 'Choose a camera to show it on the map.',
  cameraListItem: '{label} · {location} · {distance}',
  // Parking
  parkingSection: 'Parking near your destination',
  parkingStop: 'PARKING STOP', destinationLabel: 'DESTINATION',
  parkingUnavailable: 'Parking places are temporarily unavailable.', parkingKicker: 'ARRIVE WITH A PLAN',
  parkingTitle: 'Parking near your destination',
  parkingSourceAt: 'Source: AT Open GIS · total spaces are not live availability',
  parkingSourceSearch: 'Place search · live spaces unavailable', parkingSourceLink: 'AT source ↗',
  parkingSelectedSummary: 'Driving to {parking} · {distance} from {destination} as the crow flies.',
  parkingIntro: 'Choose a parking place for the driving leg, then continue on foot. Distances are straight line.',
  parkingHint: 'Parking: {parking} · then walk to {destination}',
  parkingLoading: 'Finding nearby parking…', parkingNone: 'No listed parking places nearby.', parkingPlace: 'Parking place',
  parkingTotalSpaces: '{count} total spaces', parkingAccessible: '{count} accessible', parkingClearance: '{meters}m clearance',
  parkingDriveDirect: 'Drive to destination instead', parkingRates: 'AT rates & rules ↗', parkingDetails: 'Place details ↗',
  parkingWalk: 'Continue on foot →',
  // Navigation
  turnDefault: 'Continue along the route', arrived: 'Arrive at destination', nextManeuver: 'Next maneuver',
  navigationTrip: 'Navigation trip', showTripDetails: 'Show trip details', hideTripDetails: 'Hide trip details',
  navOverview: 'Route overview', gpsUnknownChip: 'GPS —', gpsChip: 'GPS ±{meters} m',
  roadFallback: 'the road', turnRoundabout: 'Enter roundabout toward {road}', turnLeft: 'Turn left onto {road}',
  turnRight: 'Turn right onto {road}', turnDepart: 'Start on {road}', turnContinue: 'Continue on {road}',
  laneRecommended: 'Recommended', laneLabel: 'Lane', laneUnknown: 'unknown',
  speakTurn: 'In {distance}, {instruction}', speakCamera: '{label} in {threshold} metres, {location}',
  navStarted: 'Navigation started. Travel safely.', navStartedTransit: 'Trip started. Follow the transit itinerary.',
  arrivedSpeech: 'You have arrived.', arrivedParkingSpeech: 'You have reached the parking place. Continue on foot to your destination.',
  upcomingCamera: 'Upcoming safety camera', fixedCamera: 'Fixed speed camera',
  rerouting: 'Rerouting…',
  rerouteOffline: 'Offline · following your last route · retrying in {seconds} s',
  rerouteRetry: 'Could not reroute · following your last route · retrying in {seconds} s',
  rerouteBusy: 'Route service busy · following your last route · retrying in {seconds} s',
  navigationEnded: 'Navigation ended.',
  voiceFailed: 'Voice playback failed. Check volume and browser speech support.',
  rotationUnavailable: 'Rotation needs a WebGL-capable vector map.',
  rotateLeft: 'Rotate map left', rotateRight: 'Rotate map right', showTraffic: 'Show traffic',
  mapLoadFailed: 'Waybi Map: {message}',
  // Journey summary
  journeyArrived: 'You made it!', journeyEnded: 'Navigation ended', journeyTravelled: 'Travelled', journeyTime: 'Journey time',
  journeyOverview: 'Journey route overview', journeyTagline: 'A little kiwi, a good journey.', keepExploring: 'Keep exploring',
  // Place card
  poiClose: 'Close place', poiFavorite: 'Save place', poiFavoriteRemove: 'Remove saved place', poiNavigate: 'Navigate here',
  poiWebsite: 'Website ↗', poiMyPlace: 'My place', poiNotePlaceholder: 'Write a private note…', poiNoteLabel: 'Private note',
  poiSaveNote: 'Save note', poiMyReview: 'My review', poiMyRating: 'My rating', poiReviewPlaceholder: 'Write a review for your own records',
  poiReviewLabel: 'Private review', poiSaveReview: 'Save my review', poiReviews: 'Place reviews', poiRatings: '{rating} · {count} ratings',
  poiOperational: 'Operational', poiViewSource: 'View source ↗', poiTypeFallback: 'OpenStreetMap',
  poiReviewHintSignedIn: 'Private to your Waybi account', poiReviewHintGuest: 'Sign in to write a private review',
  poiAccountHintSignedIn: 'Synced to {email}', poiAccountHintGuest: 'Sign in to sync favorites and notes',
  signInToSync: 'Sign in in Settings to sync favorites and notes.', savedToAccount: 'Saved to your account',
  signInToReview: 'Sign in to review a place.', reviewSaved: 'Private review saved',
  // Settings
  settingsEyebrow: 'NAVIGATION', settingsTitle: 'Navigation settings', closeSettings: 'Close settings',
  language: 'Language', languageDescription: 'App and voice alerts',
  voice: 'Voice guidance', voiceDescription: 'Turns and cameras', voiceTest: 'Test voice ▶',
  voiceOnSpeech: 'Voice guidance is on.', voiceTestSpeech: 'Voice test. Watch the road ahead.',
  laneGuidance: 'Recommended lanes', laneGuidanceDescription: 'Show when route data includes lane guidance',
  keepScreenAwake: 'Keep screen awake', keepScreenAwakeDescription: 'Prevent auto-lock while navigating',
  theme: 'Appearance', themeDescription: 'Follow the system, or choose light or dark',
  themeSystem: 'System', themeLight: 'Light', themeDark: 'Dark',
  drivingMode: 'Driving mode', drivingDescription: 'Keep the screen awake and track location in foreground',
  drivingStarted: 'Active', drivingStopped: 'Inactive',
  backgroundTitle: 'Background navigation',
  backgroundDescription: 'Keep the web map open during navigation. A browser may pause GPS and voice guidance when locked or in the background.',
  // Data dialog
  dataEyebrow: 'DATA SOURCE', dataTitle: 'Camera data', closeData: 'Close data details', source: 'Data source',
  sourceUpdated: 'Source updated', lastChecked: 'Last checked', syncStatus: 'Sync status',
  autoSync: 'Automatic sync', autoSyncDescription: 'The server automatically refreshes the official NZTA list. Validated data is kept if syncing fails. Camera direction and lane data are not provided by NZTA; alerts are advisory.',
  sourceLink: 'View official NZTA list ↗',
  // Updates
  updateReady: 'A new version of Waybi is ready.', updateReload: 'Reload', updateLater: 'Later',
  // Account forms
  accountTitle: 'Welcome to Waybi', accountGuest: 'Guest mode is always available. Sign in to sync your trips and places.',
  accountSignedIn: 'Signed in as {email}', accountEmail: 'Email', accountPassword: 'Password', accountCode: '6-digit code',
  accountLogin: 'Sign in', accountContinueEmail: 'Continue with email', accountVerify: 'Verify and continue',
  accountLogout: 'Sign out', accountWarning: 'New here? Verifying your email creates your account automatically.',
  accountError: 'Could not connect to your account.', accountUsePassword: 'Sign in with a password', accountUseCode: 'Use an email code instead',
  accountCheckInbox: 'Check your inbox. Your code expires in 10 minutes.', accountResend: 'Resend code', accountChangeEmail: 'Change email',
  accountRetryIn: 'Try again in {seconds} seconds.', accountCodeSent: 'A new code has been sent.',
  accountTerms: 'Terms of use', accountPrivacy: 'Privacy policy',
  // Dashboard
  dashboardDocumentTitle: 'Dashboard · Waybi', dashboardWebsite: 'Website', dashboardOpenNavigator: 'Open navigator',
  dashboardAccountLabel: 'ACCOUNT', dashboardTitle: 'Your Waybi', dashboardIntro: 'Sign in to keep recent trips, favorite places, notes and personal reviews together.',
  dashboardHelpTitle: 'Navigation stays available', dashboardHelpBody: 'You can always use Waybi in guest mode. An account adds synchronization and history.',
  dashboardContinueGuest: 'Continue as guest →', dashboardLabel: 'DASHBOARD',
  dashboardGreetingGuest: 'Your activity, all in one place.', dashboardGreetingSignedIn: 'Welcome back. Here’s your recent activity.',
  dashboardEmptyTitle: 'Sign in to make Waybi yours', dashboardEmptyBody: 'Navigation stays available without an account. Sign in when you want history and personal context to follow you.',
  dashboardRecentTitle: 'Recent navigation', dashboardRecentBody: 'Keep a lightweight history of destinations, travel modes and trip distance.',
  dashboardSavedTitle: 'Saved places + notes', dashboardSavedBody: 'Favorite places and keep private notes for the locations you return to.',
  dashboardReviewsTitle: 'Your own reviews', dashboardReviewsBody: 'Keep personal ratings and comments private in your Waybi account.',
  dashboardOptional: 'Account features are optional. Core navigation works in guest mode.',
  switchToChinese: '切换到中文', switchToEnglish: 'Switch to English', languageToggleLabel: '中文',
  // Profile view
  profileGuest: 'Navigation works as a guest. Sign in to sync trips, favorites and your own reviews.',
  profileSignIn: 'Sign in or register', profileTrips: 'Trips', profileFavorites: 'Favorites', profileReviews: 'Reviews',
  profileRecent: 'Recent navigation', profileNoTrips: 'No trips recorded yet.', profileFavoritePlaces: 'Favorite places and notes',
  profileNoPlaces: 'No saved places yet.', profileMyReviews: 'My reviews', profileNoReviews: 'No reviews yet. Open a place card to write one.',
  modeNameDrive: 'Drive', modeNameTransit: 'Transit', modeNameWalk: 'Walk', modeNameBicycle: 'Bike',
  // Status pages
  notFoundTitle: 'This road ends here.', notFoundBody: 'The page you asked for does not exist. Head back to Waybi or open the web map.',
  notFoundKicker: '404 · WRONG TURN', returnHome: 'Waybi home', openApp: 'Open Waybi',
  loadFailedTitle: 'Waybi could not load this page.', loadFailedBody: 'Refresh the page or return to the website.', loadFailedHome: 'Return home',
  loadingDashboard: 'Loading your Waybi dashboard…',
  subscribeKicker: 'WAYBI PLUS', subscribeDashboard: 'Open your dashboard',
  subscribeSuccessTitle: 'Thanks — you’re all set.', subscribeSuccessBody: 'Your payment went through. Waybi Plus becomes active on your account within a few moments; reopen the app if it does not show yet.',
  subscribeCancelledTitle: 'Checkout cancelled.', subscribeCancelledBody: 'No payment was taken. You can keep using Waybi as before and subscribe any time.',
  subscribeManageTitle: 'Your Waybi subscription', subscribeManageBody: 'Manage Waybi Plus from your account. Subscriptions bought through the App Store are managed in your Apple account settings.',
};

export type MessageKey = keyof typeof en;

const zh: Record<MessageKey, string> = {
  title: 'Waybi · 网页地图', description: '独立地图、路线规划与新西兰固定摄像头信息',
  map: 'Waybi 导航地图', home: 'Waybi 首页', brandAlt: 'Waybi 地图与导航',
  settings: '打开设置', profile: '账户总览', locating: '定位中', gpsUnavailable: 'GPS 不可用',
  enableLocation: '使用我的位置', permissionDenied: '定位被阻止', gpsTemporary: '定位暂不可用',
  gpsAccuracyBadge: 'GPS {meters} 米',
  permissionHelpIos: '定位被阻止。请在 iPhone 打开“设置 → 隐私与安全性 → 定位服务 → Safari 网站”，选择“使用 App 期间”，然后重新加载 Waybi 并点按 GPS。',
  permissionHelpIosApp: '定位被阻止。请在 iPhone 打开“设置 → 隐私与安全性 → 定位服务”，允许 Safari 网站使用定位，然后重新打开 Waybi 并点按 GPS。',
  permissionHelpAndroid: '定位被阻止。请点按地址栏旁的网站设置图标 → 权限 → 位置信息 → 允许，并确认 Android 快捷设置中已开启定位，然后点按 GPS。',
  permissionHelpDesktop: '定位被阻止。请点击地址栏旁的网站设置图标，允许 waybi.co 使用位置信息，然后再次点按 GPS。',
  searchPanel: '路线搜索', origin: '当前位置 · 点击可改起点', originLabel: '起点', destination: '搜索目的地',
  useGps: '使用实时位置', searchButton: '搜索目的地', follow: '跟随位置', recenter: '回到当前位置',
  noGps: '等待 GPS 定位。', minQuery: '请输入至少 3 个字符。', searching: '搜索中…',
  noResults: '未找到地点，请换个关键词。', searchFailed: '搜索失败',
  searchOffline: '网络似乎已断开。请检查网络连接后再搜索。',
  searchBusy: '搜索服务繁忙，请 {seconds} 秒后重试。',
  suggestionsOffline: '离线时无法提供建议。恢复网络后按回车即可搜索。',
  suggestionsBusy: '实时建议暂停片刻，按回车仍可搜索。',
  suggestionsLabel: '搜索建议', suggestionsCount: '有 {count} 条建议，可用上下方向键选择。',
  retry: '重试',
  stopPlaceholder: '添加途经点', stopLabel: '途经点', stopSearch: '搜索途经点', removeStop: '移除途经点 {name}',
  currentPlace: '当前位置', guestRecent: '最近的目的地',
  autocompleteUnavailable: '实时补全需要配置地址服务；按回车仍可搜索。',
  routeCalculating: '正在计算路线…', destinationFallback: '目的地', routeError: '路线暂不可用',
  routeFailed: '路线计算失败', chooseOrigin: '请选择起点，或允许 GPS 定位。',
  noRouteAvailable: '暂无可用路线，请调整地点或稍后重试。',
  routeBusy: '路线服务繁忙，Waybi 将在 {seconds} 秒后重试。',
  routeOffline: '网络似乎已断开，Waybi 会在恢复后重试路线。',
  stateReady: '准备出发', stateCalculating: '正在规划路线', stateRouteReady: '路线已就绪', stateRouteError: '路线出错',
  stateDriving: '驾驶模式', stateGuidance: '导航中', stateArrived: '已到达', stateParkingReached: '已到停车点',
  initialTitle: '规划你的下一程', start: '开始导航', startShort: '开始导航', startTrip: '开始行程',
  stop: '结束导航', cancelDestination: '取消', clearDestination: '取消目的地',
  modeDrive: '驾车', modeTransit: '公交', modeWalk: '步行', modeBike: '骑行', travelModes: '出行方式',
  recommended: '推荐', routeAlternatives: '备选路线',
  trafficNormal: '畅通', trafficSlow: '缓行', trafficHeavy: '拥堵',
  trafficUnavailable: '实时交通区间暂不可用；路线颜色不代表当前路况。',
  trafficAdvisory: '路况提示', roadAdvisory: '沿途道路提示',
  heavySectionsOne: '前方 1 段严重拥堵', heavySectionsOther: '前方 {count} 段严重拥堵',
  slowSectionsOne: '前方 1 段缓行', slowSectionsOther: '前方 {count} 段缓行',
  transitFallback: '公共交通', transitStopsOne: '1 站', transitStopsOther: '{count} 站',
  addStop: '＋ 添加途经点', saveRoute: '♡ 保存',
  routeSavedAccount: '路线已保存到账户', routeSavedSession: '路线仅保留到本次会话',
  durationMinutes: '{minutes} 分钟', durationHours: '{hours} 小时', durationHoursMinutes: '{hours} 小时 {minutes} 分钟',
  expandSheet: '展开路线详情', collapseSheet: '收起路线详情',
  speedLimit: '当前限速', nextCamera: '下一摄像头', gpsAccuracy: 'GPS 精度', routeSteps: '路线步骤',
  camerasAlong: '沿途摄像头', distance: '路程', arrival: '预计到达', dataDetails: '数据详情 ↗', cameraData: '摄像头数据 ↗',
  camerasLoading: '正在加载 NZTA 摄像头…', camerasUnavailable: '摄像头数据暂不可用',
  cameraCount: '个 NZTA 固定摄像头', cached: '缓存', neverChecked: '尚未检查',
  synced: '已同步', stale: '官方连接失败，使用缓存', offline: '离线缓存', seed: '初始 CSV',
  voiceOn: '语音 ✓', voiceOff: '语音 关闭', lanesOn: '车道 ✓', lanesOff: '车道 关闭',
  accountSynced: '账号已同步', guestMode: '访客模式', speedLimitBadge: '限速 {value}', speedLimitUnknown: '限速 —',
  currentSpeed: '当前车速', speedUnit: '公里/时',
  cameraList: '摄像头列表', cameraListRoute: '本路线上的摄像头', cameraListNearby: '地图中心附近的摄像头',
  cameraListEmpty: '这里没有可列出的摄像头。', cameraListHint: '选择摄像头即可在地图上查看。',
  cameraListItem: '{label} · {location} · {distance}',
  parkingSection: '终点附近停车',
  parkingStop: '停车点', destinationLabel: '目的地',
  parkingUnavailable: '停车地点暂时无法加载。', parkingKicker: '到达前，先看停车',
  parkingTitle: '终点附近停车',
  parkingSourceAt: '来源：AT Open GIS · 总车位并非实时空位',
  parkingSourceSearch: '地点搜索 · 不提供实时空位', parkingSourceLink: 'AT 原始数据 ↗',
  parkingSelectedSummary: '已选 {parking}，距 {destination} 约 {distance}（直线距离）。',
  parkingIntro: '先选停车点，导航会以它为驾车终点；距离为直线距离，停车后可继续步行。',
  parkingHint: '停车：{parking} · 之后步行到 {destination}',
  parkingLoading: '正在寻找停车点…', parkingNone: '附近暂无已收录停车点。', parkingPlace: '停车地点',
  parkingTotalSpaces: '总车位 {count}', parkingAccessible: '无障碍 {count}', parkingClearance: '限高 {meters} 米',
  parkingDriveDirect: '改为直接到目的地', parkingRates: 'AT 费用与规则 ↗', parkingDetails: '查看地点 ↗',
  parkingWalk: '继续步行到目的地 →',
  turnDefault: '沿路线行驶', arrived: '到达目的地', nextManeuver: '下一步转弯',
  navigationTrip: '导航行程', showTripDetails: '展开行程详情', hideTripDetails: '收起行程详情',
  navOverview: '路线总览', gpsUnknownChip: 'GPS —', gpsChip: 'GPS ±{meters} 米',
  roadFallback: '道路', turnRoundabout: '进入环岛，驶向 {road}', turnLeft: '左转进入 {road}',
  turnRight: '右转进入 {road}', turnDepart: '出发，沿 {road} 行驶', turnContinue: '继续沿 {road} 行驶',
  laneRecommended: '推荐车道', laneLabel: '车道', laneUnknown: '未知',
  speakTurn: '{distance}后，{instruction}', speakCamera: '前方 {threshold} 米{label}，{location}',
  navStarted: '导航开始，请注意安全。', navStartedTransit: '行程开始，请按照换乘信息出行。',
  arrivedSpeech: '已到达目的地。', arrivedParkingSpeech: '已到达停车点。停车后请继续步行到目的地。',
  upcomingCamera: '前方摄像头提醒', fixedCamera: '固定测速摄像头',
  rerouting: '正在重新规划路线…',
  rerouteOffline: '网络离线 · 沿原路线行驶 · {seconds} 秒后重试',
  rerouteRetry: '重新规划失败 · 沿原路线行驶 · {seconds} 秒后重试',
  rerouteBusy: '路线服务繁忙 · 沿原路线行驶 · {seconds} 秒后重试',
  navigationEnded: '导航已结束。',
  voiceFailed: '语音播放失败，请检查音量和浏览器语音权限。',
  rotationUnavailable: '旋转需要支持 WebGL 的矢量地图。',
  rotateLeft: '向左旋转地图', rotateRight: '向右旋转地图', showTraffic: '显示路况',
  mapLoadFailed: 'Waybi 地图：{message}',
  journeyArrived: '到啦！', journeyEnded: '本次导航已结束', journeyTravelled: '行驶距离', journeyTime: '行程用时',
  journeyOverview: '行程路线总览', journeyTagline: '小 kiwi 陪你，又完成了一段旅程。', keepExploring: '继续探索',
  poiClose: '关闭地点', poiFavorite: '收藏地点', poiFavoriteRemove: '取消收藏', poiNavigate: '导航到这里',
  poiWebsite: '网站 ↗', poiMyPlace: '我的地点', poiNotePlaceholder: '写下自己的备注…', poiNoteLabel: '私人备注',
  poiSaveNote: '保存备注', poiMyReview: '我的评价', poiMyRating: '我的评分', poiReviewPlaceholder: '写下自己的私人评价',
  poiReviewLabel: '私人评价', poiSaveReview: '保存我的评价', poiReviews: '地点评价', poiRatings: '{rating} · {count} 条评分',
  poiOperational: '营业中', poiViewSource: '查看来源 ↗', poiTypeFallback: 'OpenStreetMap',
  poiReviewHintSignedIn: '仅保存在你的 Waybi 账户', poiReviewHintGuest: '登录后撰写私人评价',
  poiAccountHintSignedIn: '同步到 {email}', poiAccountHintGuest: '登录后同步收藏和备注',
  signInToSync: '请先在设置中登录，再同步收藏和备注。', savedToAccount: '已同步到账号',
  signInToReview: '请先登录再评价地点。', reviewSaved: '私人评价已保存',
  settingsEyebrow: '导航', settingsTitle: '导航设置', closeSettings: '关闭设置',
  language: '语言', languageDescription: '界面及语音提示',
  voice: '语音提示', voiceDescription: '转弯及摄像头', voiceTest: '试听语音 ▶',
  voiceOnSpeech: '语音提示已开启。', voiceTestSpeech: '语音测试。前方请注意路况。',
  laneGuidance: '推荐车道', laneGuidanceDescription: '路线数据包含车道信息时显示',
  keepScreenAwake: '导航时屏幕常亮', keepScreenAwakeDescription: '导航期间防止自动锁屏',
  theme: '外观', themeDescription: '跟随系统，或选择浅色、深色',
  themeSystem: '跟随系统', themeLight: '浅色', themeDark: '深色',
  drivingMode: '驾驶模式', drivingDescription: '保持屏幕唤醒，持续前台定位',
  drivingStarted: '已启动', drivingStopped: '未启动',
  backgroundTitle: '后台导航说明',
  backgroundDescription: '网页导航时请保持页面在前台。切到后台或锁屏后，浏览器可能暂停定位与语音。',
  dataEyebrow: '数据来源', dataTitle: '摄像头数据', closeData: '关闭数据详情', source: '数据来源',
  sourceUpdated: '官方更新时间', lastChecked: '最近检查', syncStatus: '同步状态',
  autoSync: '自动同步', autoSyncDescription: '服务器自动更新 NZTA 官方列表。同步失败时保留最近一次经过校验的数据。摄像头方向和车道未在官方列表中提供，提醒仅作辅助。',
  sourceLink: '查看 NZTA 官方列表 ↗',
  updateReady: 'Waybi 新版本已就绪。', updateReload: '重新加载', updateLater: '稍后',
  accountTitle: '欢迎来到 Waybi', accountGuest: '随时可使用访客模式。登录后同步行程和收藏地点。',
  accountSignedIn: '已登录 {email}', accountEmail: '邮箱', accountPassword: '密码', accountCode: '6 位验证码',
  accountLogin: '登录', accountContinueEmail: '使用邮箱继续', accountVerify: '验证并继续',
  accountLogout: '退出登录', accountWarning: '首次使用？验证邮箱后将自动创建账号。',
  accountError: '无法连接账户。', accountUsePassword: '使用密码登录', accountUseCode: '改用邮箱验证码',
  accountCheckInbox: '请查收邮件，验证码 10 分钟内有效。', accountResend: '重新发送', accountChangeEmail: '更换邮箱',
  accountRetryIn: '请在 {seconds} 秒后重试。', accountCodeSent: '新验证码已发送。',
  accountTerms: '使用条款', accountPrivacy: '隐私政策',
  dashboardDocumentTitle: '个人面板 · Waybi', dashboardWebsite: '网站', dashboardOpenNavigator: '打开导航',
  dashboardAccountLabel: '账户', dashboardTitle: '你的 Waybi', dashboardIntro: '登录后可集中查看最近行程、收藏地点、备注和个人评价。',
  dashboardHelpTitle: '导航始终可用', dashboardHelpBody: '你随时可以用访客模式使用 Waybi。账户只增加同步与历史记录。',
  dashboardContinueGuest: '以访客身份继续 →', dashboardLabel: '个人面板',
  dashboardGreetingGuest: '你的活动，集中在一个页面。', dashboardGreetingSignedIn: '欢迎回来，这是你的近期活动。',
  dashboardEmptyTitle: '登录，让 Waybi 更懂你', dashboardEmptyBody: '不登录也能导航。需要历史记录和个人信息跟随你时再登录。',
  dashboardRecentTitle: '最近导航', dashboardRecentBody: '轻量记录目的地、出行方式和行程距离。',
  dashboardSavedTitle: '收藏地点与备注', dashboardSavedBody: '收藏常去的地点，并为它们写下私人备注。',
  dashboardReviewsTitle: '自己的评价', dashboardReviewsBody: '个人评分和评论仅保存在你的 Waybi 账户中。',
  dashboardOptional: '账户功能为可选项，核心导航在访客模式下即可使用。',
  switchToChinese: '切换到中文', switchToEnglish: 'Switch to English', languageToggleLabel: 'EN',
  profileGuest: '访客可直接使用导航。登录后可在这里同步行程、收藏和自己的评价。',
  profileSignIn: '登录或注册', profileTrips: '次导航', profileFavorites: '个收藏', profileReviews: '条评价',
  profileRecent: '最近导航', profileNoTrips: '还没有导航记录。', profileFavoritePlaces: '收藏地点与备注',
  profileNoPlaces: '还没有收藏地点。', profileMyReviews: '我的评价', profileNoReviews: '还没有评价。打开地点卡片即可撰写。',
  modeNameDrive: '驾车', modeNameTransit: '公交', modeNameWalk: '步行', modeNameBicycle: '骑行',
  notFoundTitle: '这条路走到头了。', notFoundBody: '你访问的页面不存在。返回 Waybi 首页，或打开网页地图。',
  notFoundKicker: '404 · 走错路了', returnHome: 'Waybi 首页', openApp: '打开 Waybi',
  loadFailedTitle: 'Waybi 无法加载此页面。', loadFailedBody: '请刷新页面，或返回网站首页。', loadFailedHome: '返回首页',
  loadingDashboard: '正在加载你的 Waybi 个人面板…',
  subscribeKicker: 'WAYBI PLUS', subscribeDashboard: '打开个人面板',
  subscribeSuccessTitle: '谢谢，一切就绪。', subscribeSuccessBody: '付款已完成。Waybi Plus 将在片刻后在你的账户中生效；如果还没显示，请重新打开 App。',
  subscribeCancelledTitle: '已取消结账。', subscribeCancelledBody: '没有产生任何扣款。你可以照常使用 Waybi，随时再订阅。',
  subscribeManageTitle: '你的 Waybi 订阅', subscribeManageBody: '可在账户中管理 Waybi Plus。通过 App Store 购买的订阅请在 Apple 账户设置中管理。',
};

const messages: Record<Language, Record<MessageKey, string>> = { en, zh };

export function isMessageKey(key: string): key is MessageKey { return Object.prototype.hasOwnProperty.call(en, key); }

/** Looks up a message and fills `{placeholders}`. */
export function t(language: Language, key: MessageKey, params?: Record<string, string | number>): string {
  const template = messages[language][key] ?? en[key];
  if (!params) return template;
  return template.replace(/\{(\w+)\}/g, (match, name: string) => (name in params ? String(params[name]) : match));
}

/** Picks the singular or plural message for `count`. */
export function plural(language: Language, count: number, one: MessageKey, other: MessageKey) {
  return t(language, count === 1 ? one : other, { count });
}

/** Duration in the active language: "5 min" / "1 h 20 min" / "5 分钟". */
export function formatDuration(seconds: number | null | undefined, language: Language = 'en') {
  if (!Number.isFinite(seconds) || !seconds) return '—';
  const minutes = Math.max(1, Math.round((seconds as number) / 60));
  if (minutes < 60) return t(language, 'durationMinutes', { minutes });
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return remainder ? t(language, 'durationHoursMinutes', { hours, minutes: remainder }) : t(language, 'durationHours', { hours });
}

export function localeFor(language: Language) { return language === 'zh' ? 'zh-NZ' : 'en-NZ'; }

const ATTRIBUTES = [['data-i18n-aria-label', 'aria-label'], ['data-i18n-placeholder', 'placeholder'], ['data-i18n-title', 'title'], ['data-i18n-alt', 'alt']] as const;

/** Resolves every `data-i18n*` attribute under `root`. */
export function translateTree(language: Language, root: ParentNode = document) {
  root.querySelectorAll<HTMLElement>('[data-i18n]').forEach((node) => {
    const key = node.dataset.i18n || '';
    if (isMessageKey(key)) node.textContent = t(language, key);
  });
  for (const [source, target] of ATTRIBUTES) {
    root.querySelectorAll<HTMLElement>(`[${source}]`).forEach((node) => {
      const key = node.getAttribute(source) || '';
      if (isMessageKey(key)) node.setAttribute(target, t(language, key));
    });
  }
}

export function applyUiLanguage(language: Language) {
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  document.title = t(language, 'title');
  document.querySelector('meta[name="description"]')?.setAttribute('content', t(language, 'description'));
  translateTree(language);
}
