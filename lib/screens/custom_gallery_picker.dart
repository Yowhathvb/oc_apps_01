import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

class CustomGalleryPicker extends StatefulWidget {
  final bool showVideoTab;
  final bool showTextTab;
  final String initialTab;

  const CustomGalleryPicker({
    super.key,
    this.showVideoTab = false,
    this.showTextTab = false,
    this.initialTab = 'foto',
  });

  @override
  State<CustomGalleryPicker> createState() => _CustomGalleryPickerState();
}

class _CustomGalleryPickerState extends State<CustomGalleryPicker> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _mediaList = [];
  
  bool _isLoadingGallery = true;
  bool _isCameraInitialized = false;

  late bool _isVideoMode;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _isVideoMode = widget.initialTab == 'video';
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _fetchAlbums();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController != null) {
        _initCamera();
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: true, // Enable audio for video recording
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      print("Camera init error: $e");
    }
  }

    int _currentCameraIndex = 0;

  void _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    
    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras!.length;
    
    setState(() {
      _isCameraInitialized = false;
    });
    
    await _cameraController?.dispose();
    
    _cameraController = CameraController(
      _cameras![_currentCameraIndex],
      ResolutionPreset.high,
      enableAudio: true,
    );
    
    await _cameraController!.initialize();
    
    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  Future<void> _fetchAlbums() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth) {
      // Fetch albums sorted by newest first (common = image + video)
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      if (albums.isNotEmpty) {
        if (mounted) {
          setState(() {
            _albums = albums;
            _selectedAlbum = albums.first;
          });
        }
        await _loadAlbumMedia(_selectedAlbum!);
      } else {
        if (mounted) setState(() => _isLoadingGallery = false);
      }
    } else {
      if (mounted) setState(() => _isLoadingGallery = false);
    }
  }

  Future<void> _loadAlbumMedia(AssetPathEntity album) async {
    setState(() => _isLoadingGallery = true);
    List<AssetEntity> media = await album.getAssetListPaged(page: 0, size: 100);
    if (mounted) {
      setState(() {
        _mediaList = media;
        _isLoadingGallery = false;
      });
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final XFile picture = await _cameraController!.takePicture();
        File savedFile = File(picture.path);
        
        // Mirror the image horizontally if it was taken with the front camera
        if (_cameraController!.description.lensDirection == CameraLensDirection.front) {
          final bytes = await savedFile.readAsBytes();
          img.Image? decodedImage = img.decodeImage(bytes);
          if (decodedImage != null) {
            decodedImage = img.flipHorizontal(decodedImage);
            await savedFile.writeAsBytes(img.encodeJpg(decodedImage, quality: 90));
          }
        }

        if (mounted) {
          Navigator.pop(context, savedFile);
        }
      } catch (e) {
        print("Take picture error: $e");
      }
    }
  }

  Future<void> _startVideoRecording() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.startVideoRecording();
        if (mounted) {
          setState(() {
            _isRecording = true;
          });
        }
      } catch (e) {
        print("Start video error: $e");
      }
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
      try {
        final XFile video = await _cameraController!.stopVideoRecording();
        if (mounted) {
          setState(() {
            _isRecording = false;
          });
          Navigator.pop(context, File(video.path));
        }
      } catch (e) {
        print("Stop video error: $e");
      }
    }
  }

  void _onShutterTap() {
    if (_isVideoMode) {
      if (_isRecording) {
        _stopVideoRecording();
      } else {
        _startVideoRecording();
      }
    } else {
      _takePicture();
    }
  }

  void _openFullGallery() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.95,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    title: _albums.isNotEmpty
                        ? Theme(
                            data: Theme.of(context).copyWith(
                              canvasColor: Colors.grey[900], // Dropdown background
                            ),
                            child: DropdownButton<AssetPathEntity>(
                              value: _selectedAlbum,
                              underline: const SizedBox(),
                              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              onChanged: (AssetPathEntity? newValue) {
                                if (newValue != null) {
                                  // Update modal state and main state
                                  setState(() {
                                    _selectedAlbum = newValue;
                                  });
                                  setModalState(() {
                                    _selectedAlbum = newValue;
                                  });
                                  _loadAlbumMedia(newValue).then((_) {
                                    if (mounted) {
                                      setModalState(() {});
                                    }
                                  });
                                }
                              },
                              items: _albums.map<DropdownMenuItem<AssetPathEntity>>((AssetPathEntity album) {
                                return DropdownMenuItem<AssetPathEntity>(
                                  value: album,
                                  child: Text(album.isAll ? "Terbaru" : album.name),
                                );
                              }).toList(),
                            ),
                          )
                        : const Text('Terbaru', style: TextStyle(color: Colors.white)),
                    centerTitle: true,
                  ),
                  Expanded(
                    child: _isLoadingGallery
                        ? const Center(child: CircularProgressIndicator(color: Colors.green))
                        : GridView.builder(
                            padding: const EdgeInsets.all(2),
                            physics: const BouncingScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                            itemCount: _mediaList.length,
                            itemBuilder: (context, index) {
                              final asset = _mediaList[index];
                              return GestureDetector(
                                onTap: () async {
                                  final File? file = await asset.file;
                                  if (file != null && mounted) {
                                    Navigator.pop(context); // close bottom sheet
                                    Navigator.pop(context, file); // return to post
                                  }
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FutureBuilder<Uint8List?>(
                                      future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                                          return Image.memory(
                                            snapshot.data!,
                                            fit: BoxFit.cover,
                                          );
                                        }
                                        return Container(color: Colors.grey[900]);
                                      },
                                    ),
                                    if (asset.type == AssetType.video)
                                      const Positioned(
                                        bottom: 4,
                                        left: 4,
                                        child: Icon(Icons.videocam, color: Colors.white, size: 18),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Fullscreen with correct aspect ratio
          if (_isCameraInitialized && _cameraController != null)
            SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Builder(
                builder: (context) {
                  final size = MediaQuery.of(context).size;
                  var scale = size.aspectRatio * _cameraController!.value.aspectRatio;
                  if (scale < 1) scale = 1 / scale;
                  return Transform.scale(
                    scale: scale,
                    child: Center(
                      child: CameraPreview(_cameraController!),
                    ),
                  );
                },
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          
          // Close button at top left
          Positioned(
            top: 40,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),

          // Top Right Flash Button
          Positioned(
            top: 40,
            right: 16,
            child: GestureDetector(
              onTap: () {
                // Toggle flash logic
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flash_off, color: Colors.white),
              ),
            ),
          ),

          // 2. Bottom Controls & Gallery Strip
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Swipe indicator (small line)
                  GestureDetector(
                    onVerticalDragEnd: (details) {
                      if (details.primaryVelocity! < 0) {
                        _openFullGallery();
                      }
                    },
                    onTap: _openFullGallery,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.transparent,
                      width: double.infinity,
                      child: Column(
                        children: [
                          Container(
                            width: 30,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white70,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_isLoadingGallery)
                             const SizedBox(height: 65, child: Center(child: CircularProgressIndicator(color: Colors.white)))
                          else
                            SizedBox(
                              height: 65,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _mediaList.length > 20 ? 20 : _mediaList.length,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                itemBuilder: (context, index) {
                                  final asset = _mediaList[index];
                                  return GestureDetector(
                                    onTap: () async {
                                      final File? file = await asset.file;
                                      if (file != null && mounted) {
                                        Navigator.pop(context, file);
                                      }
                                    },
                                    child: Container(
                                      width: 65,
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          FutureBuilder<Uint8List?>(
                                            future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                                                return Image.memory(
                                                  snapshot.data!,
                                                  fit: BoxFit.cover,
                                                );
                                              }
                                              return Container(color: Colors.grey[800]);
                                            },
                                          ),
                                          if (asset.type == AssetType.video)
                                            const Positioned(
                                              bottom: 2,
                                              left: 2,
                                              child: Icon(Icons.videocam, color: Colors.white, size: 14),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Camera Shutter Button Area
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20, top: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Gallery Icon
                        GestureDetector(
                          onTap: _openFullGallery,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.photo_library, color: Colors.white, size: 24),
                          ),
                        ),
                        // Shutter
                        GestureDetector(
                          onTap: _onShutterTap,
                          child: Container(
                            width: 75,
                            height: 75,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: Center(
                              child: Container(
                                width: 65,
                                height: 65,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isVideoMode ? Colors.red : Colors.white,
                                ),
                                child: _isRecording
                                    ? const Icon(Icons.stop, color: Colors.white, size: 30)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        // Flip Camera
                        GestureDetector(
                          onTap: _switchCamera,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 24),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bottom Text Tabs
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.showVideoTab)
                          GestureDetector(
                            onTap: () {
                              setState(() => _isVideoMode = true);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: _isVideoMode ? Colors.white24 : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Video', 
                                style: TextStyle(
                                  color: _isVideoMode ? Colors.white : Colors.white70, 
                                  fontSize: 14, 
                                  fontWeight: FontWeight.bold
                                )
                              ),
                            ),
                          ),
                        if (widget.showVideoTab)
                          const SizedBox(width: 8),
                          
                        GestureDetector(
                          onTap: () {
                            setState(() => _isVideoMode = false);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: !_isVideoMode ? Colors.white24 : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Foto', 
                              style: TextStyle(
                                color: !_isVideoMode ? Colors.white : Colors.white70, 
                                fontSize: 14, 
                                fontWeight: FontWeight.bold
                              )
                            ),
                          ),
                        ),
                        
                        if (widget.showTextTab || widget.showVideoTab)
                          const SizedBox(width: 8),
                          
                        if (widget.showTextTab)
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context, 'text');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              color: Colors.transparent,
                              child: const Text(
                                'Teks', 
                                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)
                              ),
                            ),
                          )
                        else if (widget.showVideoTab)
                          const SizedBox(width: 50), // Balancer if Teks is missing but Video is present
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
