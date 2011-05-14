dbox
====

An easy way to push and pull your Dropbox folders, with fine-grained control over what folder you are syncing, where you are syncing it to, and when you are doing it.

**IMPORTANT:** This is **not** an automated Dropbox client. It will exit after sucessfully pushing/pulling, so if you want regular updates, you can run it in cron, a loop, etc.


Installation
------------

### Get developer keys

* Follow the instructions at https://www.dropbox.com/developers/quickstart to create a Dropbox development application, and copy the application keys.

* Now either set the keys as environment variables:

```sh
$ export DROPBOX_APP_KEY=cmlrrjd3j0gbend
$ export DROPBOX_APP_SECRET=uvuulp75xf9jffl
```

Or include them in calls to dbox:

```sh
$ DROPBOX_APP_KEY=cmlrrjd3j0gbend DROPBOX_APP_SECRET=uvuulp75xf9jffl dbox ...
```
### Generate an auth token

* Make an authorize request:

```sh
$ dbox authorize
Please visit the following URL in your browser, log into Dropbox, and authorize the app you created.

http://www.dropbox.com/0/oauth/authorize?oauth_token=j2kuzfvobcpqh0g

When you have done so, press [ENTER] to continue.
```

* Visit the given URL in your browser, and then go back to the terminal and press Enter.

* Now either set the keys as environment variables:

```sh
$ export DROPBOX_AUTH_KEY=v4d7l1rez1czksn
$ export DROPBOX_AUTH_SECRET=pqej9rmnj0i1gcxr4
```

Or include them in calls to dbox:

```sh
$ DROPBOX_AUTH_KEY=v4d7l1rez1czksn DROPBOX_AUTH_SECRET=pqej9rmnj0i1gcxr4 dbox ...
```

This auth token will last for **10 years**, or when you choose to invalidate it, whichever comes first. So you really only need to do this once, and then keep them around.


Usage
-----

### Authorize

```sh
$ dbox authorize
```

### Clone an existing Dropbox folder

```sh
$ dbox clone <remote_path> [<local_path>]
```

### Create a new Dropbox folder

```sh
$ dbox create <remote_path> [<local_path>]
```

### Pull (download changes from Dropbox)

```sh
$ dbox pull [<local_path>]
```

### Push (upload changes to Dropbox)

```sh
$ dbox push [<local_path>]
```


Example
-------

```sh
$ export DROPBOX_APP_KEY=cmlrrjd3j0gbend
$ export DROPBOX_APP_SECRET=uvuulp75xf9jffl
```

```sh
$ dbox authorize
```

```sh
$ open http://www.dropbox.com/0/oauth/authorize?oauth_token=aaoeuhtns123456
```

```sh
$ export DROPBOX_AUTH_KEY=v4d7l1rez1czksn
$ export DROPBOX_AUTH_SECRET=pqej9rmnj0i1gcxr4
```

```sh
$ cd /tmp
$ dbox clone Public
$ cd Public
$ echo "Hello World" > hello.txt
$ dbox push
```

```sh
$ cat ~/Dropbox/Public/hello.txt
Hello World
$ echo "Oh, Hello" > ~/Dropbox/Public/hello.txt
```

```sh
$ dbox pull
$ cat hello.txt
Oh, Hello
```
