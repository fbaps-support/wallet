[% INCLUDE "header.tpl" %]
Use this form to change your own wallet password:
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
<table class="formtable">
<tr><th>Old Password:</th><td><input type="password" name="oldpassword" width=20></td></tr>
<tr><th>New Password:</th><td><input type="password" name="password1" width=20></td></tr>
<tr><th>Again:</th><td><input type="password" name="password2" width=20></td></tr>
<tr><td colspan="2"><input type="submit" name="newpass" value="Change password"></td></tr>
</table>
</form>
[% INCLUDE "footer.tpl" %]
