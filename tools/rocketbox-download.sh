B=https://raw.githubusercontent.com/microsoft/Microsoft-Rocketbox/master/Assets/Avatars
for e in "Adults Male_Adult_17 m022" "Adults Female_Party_02 f022" "Professions Business_Female_01 f014"; do
  set -- $e; mkdir -p src/$2
  curl -sL -o src/$2/$2.fbx $B/$1/$2/Export/$2.fbx &
  for k in body_color body_normal head_color head_normal; do curl -sL -o tga/$3_$k.tga $B/$1/$2/Textures/$3_$k.tga & done
  if [ "$3" != "m022" ]; then curl -sL -o tga/$3_opacity_color.tga $B/$1/$2/Textures/$3_opacity_color.tga & fi
done; wait
