import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_screen.dart';
import 'dart:async';

class LandingPage extends StatefulWidget {
  const LandingPage({Key? key}) : super(key: key);

  @override
  _LandingPageState createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // Increased duration for more visibility
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOutBack, // Bouncy effect
      ),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0), // Starting from further down
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutBack, // Changed to easeOutBack for more pronounced movement
    ));
    
    // Add a slight delay before starting animation
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _fadeController.forward();
      }
    });
    
    // Start animation
    _fadeController.forward();
  }
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _numPages = 3;

  final List<Map<String, dynamic>> _pages = [
    {
      'title': 'Welcome to NeuroVision',
      'description': 'Advanced face analysis and attention tracking using AI',
      'lottie': 'assets/animations/face_scan.json',
      'color': Colors.blue,
    },
    {
      'title': 'Real-time Analysis',
      'description': 'Get instant feedback on attention and focus levels',
      'lottie': 'assets/animations/analytics.json',
      'color': Colors.purple,
    },
    {
      'title': 'Get Started',
      'description': 'Begin your journey to better focus and productivity',
      'lottie': 'assets/animations/rocket.json',
      'color': Colors.teal,
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset and restart animation when page changes
    _fadeController.reset();
    _fadeController.forward();
  }

  Future<void> _onGetStarted() async {
    // Scale down and fade out the current screen with more pronounced animation
    await _fadeController.animateTo(0.0, 
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
    
    if (!mounted) return;
    
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionDuration: const Duration(milliseconds: 1200), // Increased duration
        reverseTransitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Combined scale and fade transition
          var scaleTween = Tween<double>(begin: 0.8, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOut));
          var fadeTween = Tween<double>(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOut));
              
          return FadeTransition(
            opacity: animation.drive(fadeTween),
            child: ScaleTransition(
              scale: animation.drive(scaleTween),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLastPage = _currentPage == _numPages - 1;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _pages[_currentPage]['color'].withOpacity(0.1),
                  Colors.black87,
                ],
              ),
            ),
          ),
          
          // Page content
          Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: isLastPage ? null : () => _pageController.jumpToPage(_numPages - 1),
                  child: Text(
                    isLastPage ? '' : 'SKIP',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              
              // Page view
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _numPages,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                      _fadeController.reset();
                      _fadeController.forward();
                    });
                  },
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Lottie animation with scale
                          ScaleTransition(
                            scale: Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(
                              parent: _fadeController,
                              curve: Curves.elasticOut,
                            )),
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: SlideTransition(
                                position: _slideAnimation,
                                child: SizedBox(
                                  height: size.height * 0.4,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween<double>(begin: 0.5, end: 1.0),
                                    duration: const Duration(milliseconds: 1000),
                                    curve: Curves.elasticOut,
                                    builder: (context, value, child) {
                                      return Transform.scale(
                                        scale: value,
                                        child: Lottie.asset(
                                          _pages[index]['lottie'],
                                          fit: BoxFit.contain,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                          // Title with shadow and scale
                          ScaleTransition(
                            scale: Tween<double>(begin: 0.9, end: 1.0).animate(CurvedAnimation(
                              parent: _fadeController,
                              curve: Curves.easeOutBack,
                            )),
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: SlideTransition(
                                position: _slideAnimation,
                                child: Text(
                                  _pages[index]['title'],
                                  style: GoogleFonts.poppins(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withOpacity(0.5),
                                        offset: const Offset(2, 2),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Description
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: SlideTransition(
                              position: _slideAnimation,
                              child: Text(
                                _pages[index]['description'],
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  color: Colors.white70,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              // Page indicator
              Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Page indicator dots
                    SmoothPageIndicator(
                      controller: _pageController,
                      count: _numPages,
                      effect: WormEffect(
                        dotColor: Colors.white24,
                        activeDotColor: _pages[_currentPage]['color'],
                        dotHeight: 8,
                        dotWidth: 8,
                        spacing: 8,
                      ),
                      onDotClicked: (index) => _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                    ),
                    
                    // Next/Get Started button
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: isLastPage
                          ? ElevatedButton(
                              onPressed: _onGetStarted,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _pages[_currentPage]['color'],
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: 5,
                              ),
                              child: const Text(
                                'GET STARTED',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : IconButton(
                              onPressed: isLastPage 
                              ? _onGetStarted 
                              : () {
                                  _fadeController.reverse().then((_) {
                                    if (mounted) {
                                      _pageController.nextPage(
                                        duration: const Duration(milliseconds: 800),
                                        curve: Curves.easeInOutQuart,
                                      ).then((_) {
                                        if (mounted) {
                                          _fadeController.forward();
                                        }
                                      });
                                    }
                                  });
                                }, 
                              icon: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _pages[_currentPage]['color'],
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              
              // Privacy policy and terms
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _launchURL('https://yourapp.com/privacy'),
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const Text('•', style: TextStyle(color: Colors.white54)),
                    TextButton(
                      onPressed: () => _launchURL('https://yourapp.com/terms'),
                      child: const Text(
                        'Terms of Service',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPage(Map<String, dynamic> page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lottie animation
          SizedBox(
            height: 300,
            child: Lottie.asset(
              page['lottie'],
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 40),
          // Title
          Text(
            page['title'],
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Description
          Text(
            page['description'],
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: Colors.white70,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
