export void raytrace_ispc(uniform uint32 width,
                          uniform uint32 height,
                          uniform unsigned int bitmap[])
{
  for(uniform uint32 y = 0; y < height; y++)
  {
    foreach(x = 0...width)
    {
      int index = y * width + x;
      int32 b = 0xFF;
      int32 g = y & 0xFF;
      int32 r = x & 0xFF;
      bitmap[index] = 0xFF000000 | (r << 16) | (g << 8) | (b << 0);
    }
  }
}
