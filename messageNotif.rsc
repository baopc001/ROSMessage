#电报发送消息
:global botToken
:global chatId
:local telApiUp "https://api.telegram.org/bot$botToken/sendMessage"
:local teljsonBody {"chat_id"=$chatId; "text"=$messageText}
:local teljsonBodyText [:serialize $teljsonBody to=json]
onerror error { 
    :tool fetch url=$telApiUp  \   
        http-method=post \
        http-header-field="Content-Type: application/json" \
        http-data=$teljsonBodyText  output=user as-value   \
    } do={
        :log info "发送消息可能超时"
    }   



#邮箱消息通知
:local eMail  "you email"

if ($toEmail = "yes") do={
    /tool e-mail send to="$eMail"  subject="routeros" body=$messageText
}

