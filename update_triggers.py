import sys

# 1. Update Like
path_like = r'e:\zharfann\project\our-chat\oc-platform\app\api\v1\posts\[postId]\like\route.ts'
with open(path_like, 'r', encoding='utf-8') as f:
    code_like = f.read()

code_like = code_like.replace(
    "await sendNotification(authorId, likerName, 'like', parseInt(postId), ${likerName} menyukai postingan Anda);",
    "await sendNotification(authorId, likerName, 'like', parseInt(postId), ${likerName} menyukai postingan Anda, userId);"
)
with open(path_like, 'w', encoding='utf-8') as f:
    f.write(code_like)

# 2. Update Comments
path_comment = r'e:\zharfann\project\our-chat\oc-platform\app\api\v1\posts\[postId]\comments\route.ts'
with open(path_comment, 'r', encoding='utf-8') as f:
    code_comment = f.read()

code_comment = code_comment.replace(
    "await sendNotification(authorId, commenterName, 'comment', postId, ${commenterName} mengomentari postingan Anda);",
    "await sendNotification(authorId, commenterName, 'comment', postId, ${commenterName} mengomentari postingan Anda, userId);"
)
code_comment = code_comment.replace(
    "await sendNotification(u.id, commenterName, 'comment', postId, ${commenterName} menyebut Anda di komentarnya);",
    "await sendNotification(u.id, commenterName, 'mention', postId, ${commenterName} menyebut Anda di komentarnya, userId);"
)
with open(path_comment, 'w', encoding='utf-8') as f:
    f.write(code_comment)

# 3. Update Follow
path_follow = r'e:\zharfann\project\our-chat\oc-platform\app\api\v1\users\[userId]\follow\route.ts'
with open(path_follow, 'r', encoding='utf-8') as f:
    code_follow = f.read()

code_follow = code_follow.replace(
    "await sendNotification(targetId, followerName, 'follow', myId, ${followerName} mulai mengikuti Anda);",
    "await sendNotification(targetId, followerName, 'follow', myId, ${followerName} mulai mengikuti Anda, parseInt(myId, 10));"
)
with open(path_follow, 'w', encoding='utf-8') as f:
    f.write(code_follow)

print("Updated triggers")
