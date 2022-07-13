<!doctype html>
<html lang="en-GB">
<head>
<meta charset="UTF-8">
<title>Password wallet</title>
<link rel="stylesheet" href="wallet.css">
</head>
<body>

[% IF !hidebar %]
<div class="tabbar">
[% FOREACH tab IN tabs %]
[% IF tab.2 %]
<form method="post" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
<input type="hidden" name="gotonode" value="[% tab.0 %]">
<input type="submit" class="[% tab.0 == currenttab ? "tab-selected" : "tab" %]" value="[% tab.1 %]">
</form>
[% END %]
[% END %]
</div>
[% END %]

[% IF error %]
<div class="error">
[% FOREACH msg IN error %]
[%~ msg ~%]<br>
[% END %]
</div>
[% END %]
[% IF message %]
<div class="info">
[% FOREACH msg IN message %]
[%~ msg ~%]<br>
[% END %]
</div>
[% END %]

