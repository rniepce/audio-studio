try:
    import pedalboard
    print("Pedalboard version:", getattr(pedalboard, "__version__", "unknown"))
    print("Attributes:", dir(pedalboard))
except ImportError as e:
    print("Error:", e)
