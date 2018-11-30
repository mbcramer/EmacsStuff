;;; simple-git.el --- A simpler user interface for git

;; Copyright (C) 2005, 2006, 2007, 2008, 2009 Alexandre Julliard <julliard@winehq.org>
;; A simplified UI written my Mike Cramer  <cramermb@gmail.com> based on the work
;; above.

;; Version: 1.0 of simple-git

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
;; MA 02111-1307 USA

;;; Commentary:

;; This file contains an interface for the git version control
;; system. It provides easy access to the most frequently used git
;; commands.
;;
;; To install: put this file on the load-path and place the following
;; in your .emacs file:
;;
;;    (require 'simple-git)
;;
;; To start: `M-x git-status'
;;
;; TODO
;;

;;; Compatibility:
;;  --THINK-MBC is this still true?
;; This file works on GNU Emacs 21 or later. It may work on older
;; versions but this is not guaranteed.
;;
;; It may work on XEmacs 21, provided that you first install the ewoc
;; and log-edit packages.
;;

(eval-when-compile (require 'cl))
(require 'ewoc)
(require 'log-edit)
(require 'easymenu)


;;;; Customizations
;;;; ------------------------------------------------------------

(defgroup git nil
  "A user interface for the git versioning system."
  :group 'tools)

(defcustom git-committer-name nil
  "User name to use for commits.
The default is to fall back to the repository config,
then to `add-log-full-name' and then to `user-full-name'."
  :group 'git
  :type '(choice (const :tag "Default" nil)
                 (string :tag "Name")))

(defcustom git-committer-email nil
  "Email address to use for commits.
The default is to fall back to the git repository config,
then to `add-log-mailing-address' and then to `user-mail-address'."
  :group 'git
  :type '(choice (const :tag "Default" nil)
                 (string :tag "Email")))

(defcustom git-commits-coding-system nil
  "Default coding system for the log message of git commits."
  :group 'git
  :type '(choice (const :tag "From repository config" nil)
                 (coding-system)))

(defcustom git-append-signed-off-by nil
  "Whether to append a Signed-off-by line to the commit message before editing."
  :group 'git
  :type 'boolean)

(defcustom git-reuse-status-buffer t
  "Whether `git-status' should try to reuse an existing buffer
if there is already one that displays the same directory."
  :group 'git
  :type 'boolean)

(defcustom git-per-dir-ignore-file ".gitignore"
  "Name of the per-directory ignore file."
  :group 'git
  :type 'string)

(defcustom git-show-uptodate nil
  "Whether to display up-to-date files.  i.e. files that are in sync with the local repository;"
  :group 'git
  :type 'boolean)

(defcustom git-show-ignored nil
  "Whether to display ignored files.  i.e. files that git has been told to ignore through .gitignore files or through ~/.gitconfig;"
  :group 'git
  :type 'boolean)

(defcustom git-show-unknown t
  "Whether to display unknown files.  i.e. files that have not been added to the git index;"
  :group 'git
  :type 'boolean)


(defcustom git-check-remote-repo t
"
The \"Status:\" line in the git-status windows shows the status of the local repository compared to the remote repository.
If this variable is t (non-nil), The remote repository will queried when the git-status window is refreshed to see if it has changed since the
last refresh.  Nil means the remote repository will not be checked.  If the remote repository is slow to respond or unavailable, it may be
desirable to set this to nil."
  :group 'git
  :type 'boolean)

;; default value is false, but when set to true will check
;; if the local sandbox is up-to-date before commiting (errors if not)
;; and push immediately after committing if it was... doesn't guarantee someone else's commit
;; doesn't get inbetween.. but the window is small.
(defcustom git-do-push-on-commit nil
  "Whether commits are followed immediately by a push.  Will not attempt the push or the commit if the local respository is not up to date."
  :group 'git
  :type 'boolean)

;; Note that --rebase causes the history entries for my changes to appear after the
;; new changes from the upstream branch.
;; --prune causes git to delete source files (and branches) that have been deleted in
;; the remote repository.  Not a problem as long as your changes have been committed.
;; Stashing does not work in this case because there is no file apply the stash to.
(defcustom git-pull-command "pull --rebase --prune "
  "parameters for git pull"
  :group 'git
  :type 'string)


;;--THINK  do we really want all these different faces?

(defface git-status-face
  '((((class color) (background light)) (:foreground "purple"))
    (((class color) (background dark)) (:foreground "salmon")))
  "Git mode face used to highlight added and modified files."
  :group 'git)

(defface git-unmerged-face
  '((((class color) (background light)) (:foreground "red" :bold t))
    (((class color) (background dark)) (:foreground "red" :bold t)))
  "Git mode face used to highlight unmerged files."
  :group 'git)

(defface git-unknown-face
  '((((class color) (background light)) (:foreground "goldenrod" :bold t))
    (((class color) (background dark)) (:foreground "goldenrod" :bold t)))
  "Git mode face used to highlight unknown files."
  :group 'git)

(defface git-uptodate-face
  '((((class color) (background light)) (:foreground "grey60"))
    (((class color) (background dark)) (:foreground "grey40")))
  "Git mode face used to highlight up-to-date files."
  :group 'git)

(defface git-ignored-face
  '((((class color) (background light)) (:foreground "grey60"))
    (((class color) (background dark)) (:foreground "grey40")))
  "Git mode face used to highlight ignored files."
  :group 'git)

(defface git-mark-face
  '((((class color) (background light)) (:foreground "red" :bold t))
    (((class color) (background dark)) (:foreground "tomato" :bold t)))
  "Git mode face used for the file marks."
  :group 'git)

(defface git-header-face
  '((((class color) (background light)) (:foreground "blue"))
    (((class color) (background dark)) (:foreground "blue")))
  "Git mode face used for commit headers."
  :group 'git)

(defface git-separator-face
  '((((class color) (background light)) (:foreground "brown"))
    (((class color) (background dark)) (:foreground "brown")))
  "Git mode face used for commit separator."
  :group 'git)

(defface git-permission-face
  '((((class color) (background light)) (:foreground "green" :bold t))
    (((class color) (background dark)) (:foreground "green" :bold t)))
  "Git mode face used for permission changes."
  :group 'git)

(defface git-sandbox-status-green
  '((((class color) (background light)) (:foreground "green3"))
    (((class color) (background dark)) (:foreground "green3")))
  "sandbox status is good...  No action required "
  :group 'git)

(defface git-sandbox-status-yellow
  '((((class color) (background light)) (:foreground "goldenrod"))
    (((class color) (background dark)) (:foreground "goldenrod")))
  "sandbox status will require minor attention  (such as another branch being out of date)."
  :group 'git)


(defface git-sandbox-status-orange
  '((((class color) (background light)) (:foreground "OrangeRed2"))
    (((class color) (background dark)) (:foreground "OrangeRed2")))
  "sandbox status will require minor attention  (such as another branch being out of date)"
  :group 'git)


(defface git-sandbox-status-red
  '((((class color) (background light)) (:foreground "red2"))
    (((class color) (background dark)) (:foreground "red2")))
  "sandbox has a problem such as git command failure"
  :group 'git)

;;;; Utilities
;;;; ------------------------------------------------------------

(defconst git-log-msg-separator "--- log message follows this line ---")

(defvar git-log-edit-font-lock-keywords
  `(("^\\(Author:\\|Date:\\|Merge:\\|Signed-off-by:\\)\\(.*\\)$"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face))
    (,(concat "^\\(" (regexp-quote git-log-msg-separator) "\\)$")
     (1 font-lock-comment-face))))

(defun git-get-env-strings (env)
  "Build a list of NAME=VALUE strings from a list of environment strings."
  (mapcar (lambda (entry) (concat (car entry) "=" (cdr entry))) env))

(defun git-log-cmd (param-list)
"Keeps a log of git commands issued."
(let ((oldbuf (current-buffer))
      (str "git "))
      (set-buffer (get-buffer-create "*git-cmd-log*"))
      (goto-char (point-max))
      (dolist (el param-list) (setq str (concat str " " el)))
      (insert str "\n")
      (set-buffer oldbuf)
     ))

(defun git-call-process (buffer &rest args)
  "Wrapper for call-process that sets environment strings."
  (git-log-cmd args)
  (apply #'call-process "git" nil buffer nil args))

(defun git-call-process-display-error (&rest args)
  "Wrapper for call-process that displays error messages."
  (let* ((dir default-directory)
         (buffer (get-buffer-create "*Git Command Output*"))
         (ok (with-current-buffer buffer
               (let ((default-directory dir)
                     (buffer-read-only nil))
                 (erase-buffer)
                 (eq 0 (apply #'git-call-process (list buffer t) args))))))
    (unless ok (display-message-or-buffer buffer))
    ok))

(defun git-call-process-string (&rest args)
  "Wrapper for call-process that returns the process output as a string,
or nil if the git command failed."
  (with-temp-buffer
    (and (eq 0 (apply #'git-call-process t args))
         (buffer-string))))

(defun git-call-process-string-display-error (&rest args)
  "Wrapper for call-process that displays error message and returns
the process output as a string, or nil if the git command failed."
  (with-temp-buffer
    (if (eq 0 (apply #'git-call-process (list t t) args))
        (buffer-string)
      (display-message-or-buffer (current-buffer))
      nil)))

(defun git-run-process-region (buffer start end program args)
  "Run a git process with a buffer region as input."
  (let ((output-buffer (current-buffer))
        (dir default-directory))
    (with-current-buffer buffer
      (cd dir)
      (apply #'call-process-region start end program
             nil (list output-buffer t) nil args))))

(defun git-run-command-buffer (buffer-name &rest args)
  "Run a git command, sending the output to a buffer named BUFFER-NAME."
  (let ((dir default-directory)
        (buffer (get-buffer-create buffer-name)))
    (message "Running git %s..." (car args))
    (with-current-buffer buffer
      (let ((default-directory dir)
            (buffer-read-only nil))
        (erase-buffer)
        (apply #'git-call-process buffer args)))
    (message "Running git %s...done" (car args))
    buffer))

(defun git-run-command-region (buffer start end env &rest args)
  "Run a git command with specified buffer region as input."
  (with-temp-buffer
    (if (eq 0 (if env
                  (git-run-process-region
                   buffer start end "env"
                   (append (git-get-env-strings env) (list "git") args))
                (git-run-process-region buffer start end "git" args)))
        (buffer-string)
      (display-message-or-buffer (current-buffer))
      nil)))

;; leaving this around, even though it isn't being called any where
;; I am worried that someone has a git pre-commit hook that requires
;; input.   Could be any of the git hooks for that matter.
;;  MBC
(defun git-run-hook (hook env &rest args)
  "Run a git hook and display its output if any."
  (let ((dir default-directory)
        (hook-name (expand-file-name (concat ".git/hooks/" hook))))
    (or (not (file-executable-p hook-name))
        (let (status (buffer (get-buffer-create "*Git Hook Output*")))
          (with-current-buffer buffer
            (erase-buffer)
            (cd dir)
            (setq status
                  (if env
                      (apply #'call-process "env" nil (list buffer t) nil
                             (append (git-get-env-strings env) (list hook-name) args))
                    (apply #'call-process hook-name nil (list buffer t) nil args))))
          (display-message-or-buffer buffer)
          (eq 0 status)))))

(defun git-get-string-sha1 (string)
  "Read a SHA1 from the specified string."
  (and string
       (string-match "[0-9a-f]\\{40\\}" string)
       (match-string 0 string)))

(defun git-get-committer-name ()
  "Return the name to use as GIT_COMMITTER_NAME."
  ; copied from log-edit
  (or git-committer-name
      (git-config "user.name")
      (and (boundp 'add-log-full-name) add-log-full-name)
      (and (fboundp 'user-full-name) (user-full-name))
      (and (boundp 'user-full-name) user-full-name)))

(defun git-get-committer-email ()
  "Return the email address to use as GIT_COMMITTER_EMAIL."
  ; copied from log-edit
  (or git-committer-email
      (git-config "user.email")
      (and (boundp 'add-log-mailing-address) add-log-mailing-address)
      (and (fboundp 'user-mail-address) (user-mail-address))
      (and (boundp 'user-mail-address) user-mail-address)))

(defun git-get-commits-coding-system ()
  "Return the coding system to use for commits."
  (let ((repo-config (git-config "i18n.commitencoding")))
    (or git-commits-coding-system
        (and repo-config
             (fboundp 'locale-charset-to-coding-system)
             (locale-charset-to-coding-system repo-config))
      'utf-8)))

(defun git-get-logoutput-coding-system ()
  "Return the coding system used for git-log output."
  (let ((repo-config (or (git-config "i18n.logoutputencoding")
                         (git-config "i18n.commitencoding"))))
    (or git-commits-coding-system
        (and repo-config
             (fboundp 'locale-charset-to-coding-system)
             (locale-charset-to-coding-system repo-config))
      'utf-8)))

(defun git-escape-file-name (name)
  "Escape a file name if necessary."
  (if (string-match "[\n\t\"\\]" name)
      (concat "\""
              (mapconcat (lambda (c)
                   (case c
                     (?\n "\\n")
                     (?\t "\\t")
                     (?\\ "\\\\")
                     (?\" "\\\"")
                     (t (char-to-string c))))
                 name "")
              "\"")
    name))

(defun git-success-message (text files)
  "Print a success message after having handled FILES."
  (let ((n (length files)))
    (if (equal n 1)
        (message "%s %s" text (car files))
      (message "%s %d files" text n))))

(defun git-get-top-dir (dir)
  "Retrieve the top-level directory of a git tree."
  (let ((cdup (with-output-to-string
                (with-current-buffer standard-output
                  (cd dir)
                  (unless (eq 0 (git-call-process t "rev-parse" "--show-cdup"))
                    (error "cannot find top-level git tree for %s." dir))))))
    (expand-file-name (concat (file-name-as-directory dir)
                              (car (split-string cdup "\n"))))))

;stolen from pcl-cvs
(defun git-append-to-ignore (file)
  "Add a file name to the ignore file in its directory."
  (let* ((fullname (expand-file-name file))
         (dir (file-name-directory fullname))
         (name (file-name-nondirectory fullname))
         (ignore-name (expand-file-name git-per-dir-ignore-file dir))
         (created (not (file-exists-p ignore-name))))
  (save-window-excursion
    (set-buffer (find-file-noselect ignore-name))
    (goto-char (point-max))
    (unless (zerop (current-column)) (insert "\n"))
    (insert "/" name "\n")
    (sort-lines nil (point-min) (point-max))
    (save-buffer))
  (when created
    (git-call-process nil "update-index" "--add" "--" (file-relative-name ignore-name)))
  (git-update-status-files (list (file-relative-name ignore-name)))))

; propertize definition for XEmacs, stolen from erc-compat
(eval-when-compile
  (unless (fboundp 'propertize)
    (defun propertize (string &rest props)
      (let ((string (copy-sequence string)))
        (while props
          (put-text-property 0 (length string) (nth 0 props) (nth 1 props) string)
          (setq props (cddr props)))
        string))))

;;;; Wrappers for basic git commands
;;;; ------------------------------------------------------------

(defun git-rev-parse (rev)
  "Parse a revision name and return its SHA1."
  (git-get-string-sha1
   (git-call-process-string "rev-parse" rev)))

(defun git-config (key)
  "Retrieve the value associated to KEY in the git repository config file."
  (let ((str (git-call-process-string "config" key)))
    (and str (car (split-string str "\n")))))

(defun git-symbolic-ref (ref)
  "Wrapper for the git-symbolic-ref command."
  (let ((str (git-call-process-string "symbolic-ref" ref)))
    (and str (car (split-string str "\n")))))

(defun git-update-ref (ref newval &optional oldval reason)
  "Update a reference by calling git-update-ref."
  (let ((args (and oldval (list oldval))))
    (when newval (push newval args))
    (push ref args)
    (when reason
     (push reason args)
     (push "-m" args))
    (unless newval (push "-d" args))
    (apply 'git-call-process-display-error "update-ref" args)))

(defun git-for-each-ref (&rest specs)
  "Return a list of refs using git-for-each-ref.
Each entry is a cons of (SHORT-NAME . FULL-NAME)."
  (let (refs)
    (with-temp-buffer
      (apply #'git-call-process t "for-each-ref" "--format=%(refname)" specs)
      (goto-char (point-min))
      (while (re-search-forward "^[^/\n]+/[^/\n]+/\\(.+\\)$" nil t)
	(push (cons (match-string 1) (match-string 0)) refs)))
    (nreverse refs)))

(defun git-read-tree (tree &optional index-file)
  "Read a tree into the index file."
  (let ((process-environment
         (append (and index-file (list (concat "GIT_INDEX_FILE=" index-file))) process-environment)))
    (apply 'git-call-process-display-error "read-tree" (if tree (list tree)))))

(defun git-write-tree (&optional index-file)
  "Call git-write-tree and return the resulting tree SHA1 as a string."
  (let ((process-environment
         (append (and index-file (list (concat "GIT_INDEX_FILE=" index-file))) process-environment)))
    (git-get-string-sha1
     (git-call-process-string-display-error "write-tree"))))

(defun git-commit-tree (buffer tree parent)
  "Create a commit and possibly update HEAD.
Create a commit with the message in BUFFER using the tree with hash TREE.
Use PARENT as the parent of the new commit. If PARENT is the current \"HEAD\",
update the \"HEAD\" reference to the new commit."
  (let ((author-name (git-get-committer-name))
        (author-email (git-get-committer-email))
        (subject "commit (initial): ")
        author-date log-start log-end args coding-system-for-write)
    (when parent
      (setq subject "commit: ")
      (push "-p" args)
      (push parent args))
    (with-current-buffer buffer
      (goto-char (point-min))
      (if
          (setq log-start (re-search-forward (concat "^" (regexp-quote git-log-msg-separator) "\n") nil t))
          (save-restriction
            (narrow-to-region (point-min) log-start)
            (goto-char (point-min))
            (when (re-search-forward "^Author: +\\(.*?\\) *<\\(.*\\)> *$" nil t)
              (setq author-name (match-string 1)
                    author-email (match-string 2)))
            (goto-char (point-min))
            (when (re-search-forward "^Date: +\\(.*\\)$" nil t)
              (setq author-date (match-string 1)))
            (goto-char (point-min))
            (when (re-search-forward "^Merge: +\\(.*\\)" nil t)
              (setq subject "commit (merge): ")
              (dolist (parent (split-string (match-string 1) " +" t))
                (push "-p" args)
                (push parent args))))
        (setq log-start (point-min)))
      (setq log-end (point-max))
      (goto-char log-start)
      (when (re-search-forward ".*$" nil t)
        (setq subject (concat subject (match-string 0))))
      (setq coding-system-for-write buffer-file-coding-system))
    (let ((commit
           (git-get-string-sha1
            (let ((env `(("GIT_AUTHOR_NAME" . ,author-name)
                         ("GIT_AUTHOR_EMAIL" . ,author-email)
                         ("GIT_COMMITTER_NAME" . ,(git-get-committer-name))
                         ("GIT_COMMITTER_EMAIL" . ,(git-get-committer-email)))))
              (when author-date (push `("GIT_AUTHOR_DATE" . ,author-date) env))
              (apply #'git-run-command-region
                     buffer log-start log-end env
                     "commit-tree" tree (nreverse args))))))
      (when commit (git-update-ref "HEAD" commit parent subject))
      commit)))

(defun git-empty-db-p ()
  "Check if the git db is empty (no commit done yet)."
  (not (eq 0 (git-call-process nil "rev-parse" "--verify" "HEAD"))))

(defun git-get-merge-heads ()
  "Retrieve the merge heads from the MERGE_HEAD file if present."
  (let (heads)
    (when (file-readable-p ".git/MERGE_HEAD")
      (with-temp-buffer
        (insert-file-contents ".git/MERGE_HEAD" nil nil nil t)
        (goto-char (point-min))
        (while (re-search-forward "[0-9a-f]\\{40\\}" nil t)
          (push (match-string 0) heads))))
    (nreverse heads)))

(defun git-get-commit-description (commit)
  "Get a one-line description of COMMIT."
  (let ((coding-system-for-read (git-get-logoutput-coding-system)))
    (let ((descr (git-call-process-string "log" "--max-count=1" "--pretty=oneline" commit)))
      (if (and descr (string-match "\\`\\([0-9a-f]\\{40\\}\\) *\\(.*\\)$" descr))
          (concat (substring (match-string 1 descr) 0 10) " - " (match-string 2 descr))
        descr))))

;;;; File info structure
;;;; ------------------------------------------------------------

; fileinfo structure stolen from pcl-cvs
(defstruct (git-fileinfo
            (:copier nil)
            (:constructor git-create-fileinfo (state name &optional old-perm new-perm rename-state orig-name marked))
            (:conc-name git-fileinfo->))
  marked              ;; t/nil
  state               ;; current state
  name                ;; file name
  old-perm new-perm   ;; permission flags
  rename-state        ;; rename or copy state
  orig-name           ;; original name for renames or copies
  needs-update        ;; whether file needs to be updated
  needs-refresh)      ;; whether file needs to be refreshed

(defvar git-status nil)

(defun git-set-fileinfo-state (info state)
  "Set the state of a file info."
  (unless (eq (git-fileinfo->state info) state)
    (setf (git-fileinfo->state info) state
	  (git-fileinfo->new-perm info) (git-fileinfo->old-perm info)
          (git-fileinfo->rename-state info) nil
          (git-fileinfo->orig-name info) nil
          (git-fileinfo->needs-update info) nil
          (git-fileinfo->needs-refresh info) t)))

(defun git-status-filenames-map (status func files &rest args)
  "Apply FUNC to the status files names in the FILES list.
The list must be sorted."
  (when files
    (let ((file (pop files))
          (node (ewoc-nth status 0)))
      (while (and file node)
        (let* ((info (ewoc-data node))
               (name (git-fileinfo->name info)))
          (if (string-lessp name file)
              (setq node (ewoc-next status node))
            (if (string-equal name file)
                (apply func info args))
            (setq file (pop files))))))))

(defun git-set-filenames-state (status files state)
  "Set the state of a list of named files. The list must be sorted"
  (when files
    (git-status-filenames-map status #'git-set-fileinfo-state files state)
    (unless state  ;; delete files whose state has been set to nil
      (ewoc-filter status (lambda (info) (git-fileinfo->state info))))))

(defun git-state-code (code)
  "Convert from a string to a added/deleted/modified state."
  (case (string-to-char code)
    (?M 'modified)
    (?? 'unknown)
    (?A 'added)
    (?D 'deleted)
    (?U 'unmerged)
    (?T 'modified)
    (t nil)))

(defun git-status-code-as-string (code)
  "Format a git status code as string."
  (case code
    ('modified (propertize "Modified" 'face 'git-status-face))
    ('unknown  (propertize "Unknown " 'face 'git-unknown-face))
    ('added    (propertize "Added   " 'face 'git-status-face))
    ('deleted  (propertize "Deleted " 'face 'git-status-face))
    ('unmerged (propertize "Unmerged" 'face 'git-unmerged-face))
    ('uptodate (propertize "Uptodate" 'face 'git-uptodate-face))
    ('ignored  (propertize "Ignored " 'face 'git-ignored-face))
    (t "?       ")))

(defun git-file-type-as-string (old-perm new-perm)
  "Return a string describing the file type based on its permissions."
  (let* ((old-type (lsh (or old-perm 0) -9))
	 (new-type (lsh (or new-perm 0) -9))
	 (str (case new-type
		(64  ;; file
		 (case old-type
		   (64 nil)
		   (80 "   (type change symlink -> file)")
		   (112 "   (type change subproject -> file)")))
		 (80  ;; symlink
		  (case old-type
		    (64 "   (type change file -> symlink)")
		    (112 "   (type change subproject -> symlink)")
		    (t "   (symlink)")))
		  (112  ;; subproject
		   (case old-type
		     (64 "   (type change file -> subproject)")
		     (80 "   (type change symlink -> subproject)")
		     (t "   (subproject)")))
                  (72 nil)  ;; directory (internal, not a real git state)
		  (0  ;; deleted or unknown
		   (case old-type
		     (80 "   (symlink)")
		     (112 "   (subproject)")))
		  (t (format "   (unknown type %o)" new-type)))))
    (cond (str (propertize str 'face 'git-status-face))
          ((eq new-type 72) "/")
          (t ""))))

(defun git-rename-as-string (info)
  "Return a string describing the copy or rename associated with INFO, or an empty string if none."
  (let ((state (git-fileinfo->rename-state info)))
    (if state
        (propertize
         (concat "   ("
                 (if (eq state 'copy) "copied from "
                   (if (eq (git-fileinfo->state info) 'added) "renamed from "
                     "renamed to "))
                 (git-escape-file-name (git-fileinfo->orig-name info))
                 ")") 'face 'git-status-face)
      "")))

(defun git-permissions-as-string (old-perm new-perm)
  "Format a permission change as string."
  (propertize
   (if (or (not old-perm)
           (not new-perm)
           (eq 0 (logand ?\111 (logxor old-perm new-perm))))
       "  "
     (if (eq 0 (logand ?\111 old-perm)) "+x" "-x"))
  'face 'git-permission-face))

(defun git-fileinfo-prettyprint (info)
  "Pretty-printer for the git-fileinfo structure."
  (let ((old-perm (git-fileinfo->old-perm info))
	(new-perm (git-fileinfo->new-perm info)))
    (insert (concat "   " (if (git-fileinfo->marked info) (propertize "*" 'face 'git-mark-face) " ")
		    " " (git-status-code-as-string (git-fileinfo->state info))
		    " " (git-permissions-as-string old-perm new-perm)
		    "  " (git-escape-file-name (git-fileinfo->name info))
		    (git-file-type-as-string old-perm new-perm)
		    (git-rename-as-string info)))))

(defun git-update-node-fileinfo (node info)
  "Update the fileinfo of the specified node. The names are assumed to match already."
  (let ((data (ewoc-data node)))
    (setf
     ;; preserve the marked flag
     (git-fileinfo->marked info) (git-fileinfo->marked data)
     (git-fileinfo->needs-update data) nil)
    (when (not (equal info data))
      (setf (git-fileinfo->needs-refresh info) t
            (ewoc-data node) info))))

(defun git-insert-info-list (status infolist files)
  "Insert a sorted list of file infos in the status buffer, replacing existing ones if any."
  (let* ((info (pop infolist))
         (node (ewoc-nth status 0))
         (name (and info (git-fileinfo->name info)))
         remaining)
    (while info
      (let ((nodename (and node (git-fileinfo->name (ewoc-data node)))))
        (while (and files (string-lessp (car files) name))
          (push (pop files) remaining))
        (when (and files (string-equal (car files) name))
          (setq files (cdr files)))
        (cond ((not nodename)
               (setq node (ewoc-enter-last status info))
               (setq info (pop infolist))
               (setq name (and info (git-fileinfo->name info))))
              ((string-lessp nodename name)
               (setq node (ewoc-next status node)))
              ((string-equal nodename name)
               ;; preserve the marked flag
               (git-update-node-fileinfo node info)
               (setq info (pop infolist))
               (setq name (and info (git-fileinfo->name info))))
              (t
               (setq node (ewoc-enter-before status node info))
               (setq info (pop infolist))
               (setq name (and info (git-fileinfo->name info)))))))
    (nconc (nreverse remaining) files)))

(defun git-run-diff-index (status files)
  "Run git-diff-index on FILES and parse the results into STATUS.
Return the list of files that haven't been handled."
  (let (infolist)
    (with-temp-buffer
      (apply #'git-call-process t "diff-index" "-z" "-M" "HEAD" "--" files)
      (goto-char (point-min))
      (while (re-search-forward
	      ":\\([0-7]\\{6\\}\\) \\([0-7]\\{6\\}\\) [0-9a-f]\\{40\\} [0-9a-f]\\{40\\} \\(\\([ADMUT]\\)\0\\([^\0]+\\)\\|\\([CR]\\)[0-9]*\0\\([^\0]+\\)\0\\([^\0]+\\)\\)\0"
              nil t 1)
        (let ((old-perm (string-to-number (match-string 1) 8))
              (new-perm (string-to-number (match-string 2) 8))
              (state (or (match-string 4) (match-string 6)))
              (name (or (match-string 5) (match-string 7)))
              (new-name (match-string 8)))
          (if new-name  ; copy or rename
              (if (eq ?C (string-to-char state))
                  (push (git-create-fileinfo 'added new-name old-perm new-perm 'copy name) infolist)
                (push (git-create-fileinfo 'deleted name 0 0 'rename new-name) infolist)
                (push (git-create-fileinfo 'added new-name old-perm new-perm 'rename name) infolist))
            (push (git-create-fileinfo (git-state-code state) name old-perm new-perm) infolist)))))
    (setq infolist (sort (nreverse infolist)
                         (lambda (info1 info2)
                           (string-lessp (git-fileinfo->name info1)
                                         (git-fileinfo->name info2)))))
    (git-insert-info-list status infolist files)))

(defun git-find-status-file (status file)
  "Find a given file in the status ewoc and return its node."
  (let ((node (ewoc-nth status 0)))
    (while (and node (not (string= file (git-fileinfo->name (ewoc-data node)))))
      (setq node (ewoc-next status node)))
    node))

(defun git-run-ls-files (status files default-state &rest options)
  "Run git-ls-files on FILES and parse the results into STATUS.
Return the list of files that haven't been handled."
  (let (infolist)
    (with-temp-buffer
      (apply #'git-call-process t "ls-files" "-z" (append options (list "--") files))
      (goto-char (point-min))
      (while (re-search-forward "\\([^\0]*?\\)\\(/?\\)\0" nil t 1)
        (let ((name (match-string 1)))
          (push (git-create-fileinfo default-state name 0
                                     (if (string-equal "/" (match-string 2)) (lsh ?\110 9) 0))
                infolist))))
    (setq infolist (nreverse infolist))  ;; assume it is sorted already
    (git-insert-info-list status infolist files)))

(defun git-run-ls-files-cached (status files default-state)
  "Run git-ls-files -c on FILES and parse the results into STATUS.
Return the list of files that haven't been handled."
  (let (infolist)
    (with-temp-buffer
      (apply #'git-call-process t "ls-files" "-z" "-s" "-c" "--" files)
      (goto-char (point-min))
      (while (re-search-forward "\\([0-7]\\{6\\}\\) [0-9a-f]\\{40\\} 0\t\\([^\0]+\\)\0" nil t)
	(let* ((new-perm (string-to-number (match-string 1) 8))
	       (old-perm (if (eq default-state 'added) 0 new-perm))
	       (name (match-string 2)))
	  (push (git-create-fileinfo default-state name old-perm new-perm) infolist))))
    (setq infolist (nreverse infolist))  ;; assume it is sorted already
    (git-insert-info-list status infolist files)))

(defun git-run-ls-unmerged (status files)
  "Run git-ls-files -u on FILES and parse the results into STATUS."
  (with-temp-buffer
    (apply #'git-call-process t "ls-files" "-z" "-u" "--" files)
    (goto-char (point-min))
    (let (unmerged-files)
      (while (re-search-forward "[0-7]\\{6\\} [0-9a-f]\\{40\\} [123]\t\\([^\0]+\\)\0" nil t)
        (push (match-string 1) unmerged-files))
      (setq unmerged-files (nreverse unmerged-files))  ;; assume it is sorted already
      (git-set-filenames-state status unmerged-files 'unmerged))))

(defun git-get-exclude-files ()
  "Get the list of exclude files to pass to git-ls-files."
  (let (files
        (config (git-config "core.excludesfile")))
    (when (file-readable-p ".git/info/exclude")
      (push ".git/info/exclude" files))
    (when (and config (file-readable-p config))
      (push config files))
    files))

(defun git-run-ls-files-with-excludes (status files default-state &rest options)
  "Run git-ls-files on FILES with appropriate --exclude-from options."
  (let ((exclude-files (git-get-exclude-files)))
    (apply #'git-run-ls-files status files default-state "--directory" "--no-empty-directory"
           (concat "--exclude-per-directory=" git-per-dir-ignore-file)
           (append options (mapcar (lambda (f) (concat "--exclude-from=" f)) exclude-files)))))

(defun git-update-status-files (&optional files mark-files)
  "Update the status of FILES from the index.
The FILES list must be sorted."
  (unless git-status (error "Not in git-status buffer."))
  (git-set-current-branch)
  ;; set the needs-update flag on existing files
  (if files
      (git-status-filenames-map
       git-status (lambda (info) (setf (git-fileinfo->needs-update info) t)) files)
    (ewoc-map (lambda (info) (setf (git-fileinfo->needs-update info) t) nil) git-status)
    (git-call-process nil "update-index" "--refresh")
    (when git-show-uptodate
      (git-run-ls-files-cached git-status nil 'uptodate)))
  (let ((remaining-files
          (if (git-empty-db-p) ; we need some special handling for an empty db
	      (git-run-ls-files-cached git-status files 'added)
            (git-run-diff-index git-status files))))
    (git-run-ls-unmerged git-status files)
    (when (or remaining-files (and git-show-unknown (not files)))
      (setq remaining-files (git-run-ls-files-with-excludes git-status remaining-files 'unknown "-o")))
    (when (or remaining-files (and git-show-ignored (not files)))
      (setq remaining-files (git-run-ls-files-with-excludes git-status remaining-files 'ignored "-o" "-i")))
    (unless files
      (setq remaining-files (git-get-filenames (ewoc-collect git-status #'git-fileinfo->needs-update))))
    (when remaining-files
      (setq remaining-files (git-run-ls-files-cached git-status remaining-files 'uptodate)))
    (git-set-filenames-state git-status remaining-files nil)
    (when mark-files (git-mark-files git-status files))
    (git-refresh-files)
    (git-refresh-ewoc-hf git-status)))

(defun git-mark-files (status files)
  "Mark all the specified FILES, and unmark the others."
  (let ((file (and files (pop files)))
        (node (ewoc-nth status 0)))
    (while node
      (let ((info (ewoc-data node)))
        (if (and file (string-equal (git-fileinfo->name info) file))
            (progn
              (unless (git-fileinfo->marked info)
                (setf (git-fileinfo->marked info) t)
                (setf (git-fileinfo->needs-refresh info) t))
              (setq file (pop files))
              (setq node (ewoc-next status node)))
          (when (git-fileinfo->marked info)
            (setf (git-fileinfo->marked info) nil)
            (setf (git-fileinfo->needs-refresh info) t))
          (if (and file (string-lessp file (git-fileinfo->name info)))
              (setq file (pop files))
            (setq node (ewoc-next status node))))))))

(defun git-marked-files ()
  "Return a list of all marked files, or if none a list containing just the file at cursor position."
  (unless git-status (error "Not in git-status buffer."))
  (or (ewoc-collect git-status (lambda (info) (git-fileinfo->marked info)))
      (list (ewoc-data (ewoc-locate git-status)))))

(defun git-marked-files-state (&rest states)
  "Return a sorted list of marked files that are in the specified states."
  (let ((files (git-marked-files))
        result)
    (dolist (info files)
      (when (memq (git-fileinfo->state info) states)
        (push info result)))
    (nreverse result)))

(defun git-refresh-files ()
  "Refresh all files that need it and clear the needs-refresh flag."
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-map
   (lambda (info)
     (let ((refresh (git-fileinfo->needs-refresh info)))
       (setf (git-fileinfo->needs-refresh info) nil)
       refresh))
   git-status)
  ; move back to goal column
  (when goal-column (move-to-column goal-column)))

(defun git-refresh-ewoc-hf (status)
  "Refresh the ewoc header and footer."
  (let ((branch git-current-branch)
        (head (if (git-empty-db-p) "Nothing committed yet" (git-get-commit-description "HEAD")))
        (merge-heads (git-get-merge-heads)))
	(git-set-ref-vars)
    (ewoc-set-hf status
         (format "Directory:\t%s\nURL:\t%sBranch:\t\t%s\nHead:\t\t%s%s\nStatus:\t\t%s\nStashes:\t%s\n"
                 default-directory
				 (git-call-process-string "config" "--get" "remote.origin.url")
                 (if branch branch "none (detached HEAD)")
                 head
                 (if merge-heads
                     (concat "\nMerging:    "
                             (mapconcat (lambda (str) (git-get-commit-description str)) merge-heads "\n            "))
                   "")
                 (git-upstream-status branch)

                 (propertize (replace-regexp-in-string "\n" "\n            " (git-list-stash)) 'face 'git-sandbox-status-green))
                 (if (ewoc-nth status 0) "" "    No changes."))))

(defun git-get-filenames (files)
  (mapcar (lambda (info) (git-fileinfo->name info)) files))

(defun git-update-index (index-file files)
  "Run git-update-index on a list of files."
  (let ((process-environment (append (and index-file (list (concat "GIT_INDEX_FILE=" index-file)))
                                     process-environment))
        added deleted modified)
    (dolist (info files)
      (case (git-fileinfo->state info)
        ('added (push info added))
        ('deleted (push info deleted))
        ('modified (push info modified))))
    (and
     (or (not added) (apply #'git-call-process-display-error "update-index" "--add" "--" (git-get-filenames added)))
     (or (not deleted) (apply #'git-call-process-display-error "update-index" "--remove" "--" (git-get-filenames deleted)))
     (or (not modified) (apply #'git-call-process-display-error "update-index" "--" (git-get-filenames modified))))))

;;  This should be obsolete now...   Not doing all this by hand
;;(defun git-run-pre-commit-hook ()
;;  "Run the pre-commit hook if any."
;;  (unless git-status (error "Not in git-status buffer."))
;;  (let ((files (git-marked-files-state 'added 'deleted 'modified)))
;;    (or (not files)
;;        (not (file-executable-p ".git/hooks/pre-commit"))
;;        (let ((index-file (make-temp-file "gitidx")))
;;          (unwind-protect
;;            (let ((head-tree (unless (git-empty-db-p) (git-rev-parse "HEAD^{tree}"))))
;;              (git-read-tree head-tree index-file)
;;              (git-update-index index-file files)
;;              (git-run-hook "pre-commit" `(("GIT_INDEX_FILE" . ,index-file))))
;;          (delete-file index-file))))))


(defun git-can-commit ()
  (interactive)
  "implements the predicate that commits are or are not allowed"
  (let ((unmerged (git-marked-files-state 'unmerged))
		(branch  (git-symbolic-ref "HEAD"))
		(poc nil)
		upstream-stat
		(uptodate t))

	(setq upstream-stat (git-upstream-status branch))

	(if git-do-push-on-commit
		(and (not unmerged)  ;;  no files need to be merged
			 (or (string= upstream-stat "Up to date") (string= upstream-stat "Local Only")) ;; local repo is up-to-date
			 )
	    t )))

;; This is a new implementation of git-do-commit.  The original one used "git commit-tree"
;; which didn't run all the git hooks...  Not to mention the man page included the following:
;; "This is usually not what an end user wants to run directly. See git-commit(1) instead."
(defun git-do-commit ()
  "
Perform the actual commit using the current buffer as log message.
If `git-do-push-on-commit' is non-nil will attempt to push to remote repository as well.
"
  (interactive)

  (let ((buffer (current-buffer))
		log-start
		ok
		files
		(all-files (list)) )
	(goto-char (point-min))
	(setq log-start (re-search-forward (concat "^" (regexp-quote git-log-msg-separator) "\n") nil t))

	(with-current-buffer log-edit-parent-buffer
	  (setq files (git-marked-files-state 'added 'deleted 'modified))
	  (if (not files) (error "Nothing to commit"))
	  (if (not (git-can-commit))
		  (error "There are unmerged files or local repository out of date")))

	(dolist (info files)
		  (setq all-files (cons (git-fileinfo->name info) all-files)))

	;; note to me....  apply allows the list all-files to be expanded to parameters
	(setq  ok (apply 'git-call-process-display-error "commit" "-m"
								(buffer-substring log-start (1- (point-max)) )
								all-files))

	(when ok
	  (if git-do-push-on-commit (with-current-buffer "*git-status*" (git-push)))
	  (erase-buffer)));; current buffer is the log-edit buffer
	(with-current-buffer log-edit-parent-buffer (git-refresh-status))
  )





;;;; Interactive functions
;;;; ------------------------------------------------------------

(defun git-mark-file ()
  "Mark the file that the cursor is on and move to the next one."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let* ((pos (ewoc-locate git-status))
         (info (ewoc-data pos)))
    (setf (git-fileinfo->marked info) t)
    (ewoc-invalidate git-status pos)
    (ewoc-goto-next git-status 1)))

(defun git-unmark-file ()
  "Unmark the file that the cursor is on and move to the next one."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let* ((pos (ewoc-locate git-status))
         (info (ewoc-data pos)))
    (setf (git-fileinfo->marked info) nil)
    (ewoc-invalidate git-status pos)
    (ewoc-goto-next git-status 1)))

(defun git-unmark-file-up ()
  "Unmark the file that the cursor is on and move to the previous one."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let* ((pos (ewoc-locate git-status))
         (info (ewoc-data pos)))
    (setf (git-fileinfo->marked info) nil)
    (ewoc-invalidate git-status pos)
    (ewoc-goto-prev git-status 1)))

(defun git-mark-all ()
  "Mark all files."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-map (lambda (info) (unless (git-fileinfo->marked info)
                             (setf (git-fileinfo->marked info) t))) git-status)
  ; move back to goal column after invalidate
  (when goal-column (move-to-column goal-column)))

(defun git-unmark-all ()
  "Unmark all files."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-map (lambda (info) (when (git-fileinfo->marked info)
                             (setf (git-fileinfo->marked info) nil)
                             t)) git-status)
  ; move back to goal column after invalidate
  (when goal-column (move-to-column goal-column)))

(defun git-toggle-all-marks ()
  "Toggle all file marks."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-map (lambda (info) (setf (git-fileinfo->marked info) (not (git-fileinfo->marked info))) t) git-status)
  ; move back to goal column after invalidate
  (when goal-column (move-to-column goal-column)))

(defun git-next-file (&optional n)
  "Move the selection down N files."
  (interactive "p")
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-goto-next git-status n))

(defun git-prev-file (&optional n)
  "Move the selection up N files."
  (interactive "p")
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-goto-prev git-status n))

(defun git-next-unmerged-file (&optional n)
  "Move the selection down N unmerged files."
  (interactive "p")
  (unless git-status (error "Not in git-status buffer."))
  (let* ((last (ewoc-locate git-status))
         (node (ewoc-next git-status last)))
    (while (and node (> n 0))
      (when (eq 'unmerged (git-fileinfo->state (ewoc-data node)))
        (setq n (1- n))
        (setq last node))
      (setq node (ewoc-next git-status node)))
    (ewoc-goto-node git-status last)))

(defun git-prev-unmerged-file (&optional n)
  "Move the selection up N unmerged files."
  (interactive "p")
  (unless git-status (error "Not in git-status buffer."))
  (let* ((last (ewoc-locate git-status))
         (node (ewoc-prev git-status last)))
    (while (and node (> n 0))
      (when (eq 'unmerged (git-fileinfo->state (ewoc-data node)))
        (setq n (1- n))
        (setq last node))
      (setq node (ewoc-prev git-status node)))
    (ewoc-goto-node git-status last)))

(defun git-insert-file (file)
  "Insert file(s) into the git-status buffer."
  (interactive "fInsert (show) file: ")
  (git-update-status-files (list (file-relative-name file))))

(defun git-add-file ()
  "Add marked file(s) to the index cache:  \"git update-index --add --\""
  (interactive)
  (let ((files (git-get-filenames (git-marked-files-state 'unknown 'ignored 'unmerged))))
    ;; FIXME: add support for directories
    (unless files
      (push (file-relative-name (read-file-name "File to add: " nil nil t)) files))
    (when (apply 'git-call-process-display-error "update-index" "--add" "--" files)
      (git-update-status-files files)
      (git-success-message "Added" files))))

(defun git-ignore-file ()
  "Add marked file(s) to the ignore list."
  (interactive)
  (let ((files (git-get-filenames (git-marked-files-state 'unknown))))
    (unless files
      (push (file-relative-name (read-file-name "File to ignore: " nil nil t)) files))
    (dolist (f files) (git-append-to-ignore f))
    (git-update-status-files files)
    (git-success-message "Ignored" files)))

(defun git-remove-file ()
  "Remove the marked file(s) from the local sandbox and index if the file is in the index."
  (interactive)
  (let ((files (git-get-filenames (git-marked-files-state 'added 'modified 'unknown 'uptodate 'ignored))))
    (unless files
      (push (file-relative-name (read-file-name "File to remove: " nil nil t)) files))
    (if (yes-or-no-p
         (if (cdr files)
             (format "Remove %d files? " (length files))
           (format "Remove %s? " (car files))))
        (progn
          (dolist (name files)
            (ignore-errors
              (if (file-directory-p name)
                  (delete-directory name)
                (delete-file name))))
          (when (apply 'git-call-process-display-error "update-index" "--remove" "--" files)
            (git-update-status-files files)
            (git-success-message "Removed" files)))
      (message "Aborting"))))

(defun git-revert-file ()
"
Revert changes to the marked file(s) with the contents of the local repository.
    Modified files go back to the state in the local repository.
    Added files are removed from the index.
"
  (interactive)
  (let ((files (git-marked-files-state 'added 'deleted 'modified 'unmerged))
        added modified)
    (when (and files
               (yes-or-no-p
                (if (cdr files)
                    (format "Revert %d files? " (length files))
                  (format "Revert %s? " (git-fileinfo->name (car files))))))
      (dolist (info files)
        (case (git-fileinfo->state info)
          ('added (push (git-fileinfo->name info) added))
          ('deleted (push (git-fileinfo->name info) modified))
          ('unmerged (push (git-fileinfo->name info) modified))
          ('modified (push (git-fileinfo->name info) modified))))
      ;; check if a buffer contains one of the files and isn't saved
      (dolist (file modified)
        (let ((buffer (get-file-buffer file)))
          (when (and buffer (buffer-modified-p buffer))
            (error "Buffer %s is modified. Please kill or save modified buffers before reverting." (buffer-name buffer)))))
      (let ((ok (and
                 (or (not added)
                     (apply 'git-call-process-display-error "update-index" "--force-remove" "--" added))
                 (or (not modified)
                     (apply 'git-call-process-display-error "checkout" "HEAD" modified))))
            (names (git-get-filenames files)))
        (git-update-status-files names)
        (when ok
          (dolist (file modified)
            (let ((buffer (get-file-buffer file)))
              (when buffer (with-current-buffer buffer (revert-buffer t t t)))))
          (git-success-message "Reverted" names))))))

(defun git-remove-handled ()
  "Remove handled files from the status list."
  (interactive)
  (ewoc-filter git-status
               (lambda (info)
                 (case (git-fileinfo->state info)
                   ('ignored git-show-ignored)
                   ('uptodate git-show-uptodate)
                   ('unknown git-show-unknown)
                   (t t))))
  (unless (ewoc-nth git-status 0)  ; refresh header if list is empty
    (git-refresh-ewoc-hf git-status)))

(defun git-toggle-show-uptodate ()
  "Toogle the option for showing up-to-date files:  `git-show-uptodate'"
  (interactive)
  (if (setq git-show-uptodate (not git-show-uptodate))
      (git-refresh-status)
    (git-remove-handled)))

(defun git-toggle-show-ignored ()
  "Toogle the option for showing ignored files:  `git-show-ignored'"
  (interactive)
  (if (setq git-show-ignored (not git-show-ignored))
      (progn
        (message "Inserting ignored files...")
        (git-run-ls-files-with-excludes git-status nil 'ignored "-o" "-i")
        (git-refresh-files)
        (git-refresh-ewoc-hf git-status)
        (message "Inserting ignored files...done"))
    (git-remove-handled)))

(defun git-toggle-show-unknown ()
  "Toogle the option for showing unknown files:  `git-show-unknown'"
  (interactive)
  (if (setq git-show-unknown (not git-show-unknown))
      (progn
        (message "Inserting unknown files...")
        (git-run-ls-files-with-excludes git-status nil 'unknown "-o")
        (git-refresh-files)
        (git-refresh-ewoc-hf git-status)
        (message "Inserting unknown files...done"))
    (git-remove-handled)))

(defun git-expand-directory (info)
  "Expand the directory represented by INFO to list its files."
  (when (eq (lsh (git-fileinfo->new-perm info) -9) ?\110)
    (let ((dir (git-fileinfo->name info)))
      (git-set-filenames-state git-status (list dir) nil)
      (git-run-ls-files-with-excludes git-status (list (concat dir "/")) 'unknown "-o")
      (git-refresh-files)
      (git-refresh-ewoc-hf git-status)
      t)))

(defun git-setup-diff-buffer (buffer)
  "Setup a buffer for displaying a diff."
  (let ((dir default-directory))
    (with-current-buffer buffer
      (diff-mode)
      (goto-char (point-min))
      (setq default-directory dir)
      (setq buffer-read-only t)))
  (display-buffer buffer)
  ; shrink window only if it displays the status buffer
  (when (eq (window-buffer) (current-buffer))
    (shrink-window-if-larger-than-buffer)))

(defun git-diff-file ()
  "Diff the marked file(s) against HEAD."
  (interactive)
  (let ((files (git-marked-files)))
    (git-setup-diff-buffer
     (apply #'git-run-command-buffer "*git-diff*" "diff-index" "--ignore-space-at-eol" "--full-index" "-p" "-M" "HEAD" "--" (git-get-filenames files)))))

(defun git-diff-file-merge-head (arg)
  "Diff the marked file(s) against the first merge head (or the nth one with a numeric prefix)."
  (interactive "p")
  (let ((files (git-marked-files))
        (merge-heads (git-get-merge-heads)))
    (unless merge-heads (error "No merge in progress"))
    (git-setup-diff-buffer
     (apply #'git-run-command-buffer "*git-diff*" "diff-index" "-p" "-M"
            (or (nth (1- arg) merge-heads) "HEAD") "--" (git-get-filenames files)))))

(defun git-diff-unmerged-file (stage)
  "Diff the marked unmerged file(s) against the specified stage."
  (let ((files (git-marked-files)))
    (git-setup-diff-buffer
     (apply #'git-run-command-buffer "*git-diff*" "diff-files" "-p" stage "--" (git-get-filenames files)))))

(defun git-diff-file-base ()
  "Diff the marked unmerged file(s) against the common base file."
  (interactive)
  (git-diff-unmerged-file "-1"))

(defun git-diff-file-mine ()
  "Diff the marked unmerged file(s) against my pre-merge version."
  (interactive)
  (git-diff-unmerged-file "-2"))

(defun git-diff-file-other ()
  "Diff the marked unmerged file(s) against the other's pre-merge version."
  (interactive)
  (git-diff-unmerged-file "-3"))

(defun git-diff-file-combined ()
  "Do a combined diff of the marked unmerged file(s)."
  (interactive)
  (git-diff-unmerged-file "-c"))

(defun git-diff-file-idiff ()
  "Perform an interactive diff on the current file."
  (interactive)
  (let ((files (git-marked-files-state 'added 'deleted 'modified)))
    (unless (eq 1 (length files))
      (error "Cannot perform an interactive diff on multiple files."))
    (let* ((filename (car (git-get-filenames files)))
           (buff1 (find-file-noselect filename))
           (buff2 (git-run-command-buffer (concat filename ".~HEAD~") "cat-file" "blob" (concat "HEAD:" filename))))
	  ;; below is a little ugliness for BSCI which has some carriage return lf (ie. dos) files  :(
	  (with-current-buffer buff2 (while (re-search-backward "" nil t) (replace-match "")) )
      (ediff-buffers buff1 buff2))))

(defun git-log-branch()
  "git log for the whole the current branch"
  (interactive)
  (let* ((coding-system-for-read git-commits-coding-system)
         (buffer (apply #'git-run-command-buffer "*git-log*" "log" "--name-status"  '()  )))
    (with-current-buffer buffer
      ; (git-log-mode)  FIXME: implement log mode
      (goto-char (point-min))
      (setq buffer-read-only t))
    (display-buffer buffer)))


(defun git-log-file ()
  "Display a log of changes to the marked file(s)."
  (interactive)
  (let* ((files (git-marked-files))
         (coding-system-for-read git-commits-coding-system)
         (buffer (apply #'git-run-command-buffer "*git-log*" "rev-list" "--pretty" "HEAD" "--" (git-get-filenames files))))
    (with-current-buffer buffer
      ; (git-log-mode)  FIXME: implement log mode
      (goto-char (point-min))
      (setq buffer-read-only t))
    (display-buffer buffer)))

(defun git-log-edit-files ()
  "Return a list of marked files for use in the log-edit buffer."
  (with-current-buffer log-edit-parent-buffer
    (git-get-filenames (git-marked-files-state 'added 'deleted 'modified))))

(defun git-log-edit-diff ()
  "Run a diff of the current files being committed from a log-edit buffer."
  (with-current-buffer log-edit-parent-buffer
    (git-diff-file)))

(defun git-append-sign-off (name email)
  "Append a Signed-off-by entry to the current buffer, avoiding duplicates."
  (let ((sign-off (format "Signed-off-by: %s <%s>" name email))
        (case-fold-search t))
    (goto-char (point-min))
    (unless (re-search-forward (concat "^" (regexp-quote sign-off)) nil t)
      (goto-char (point-min))
      (unless (re-search-forward "^Signed-off-by: " nil t)
        (setq sign-off (concat "\n" sign-off)))
      (goto-char (point-max))
      (insert sign-off "\n"))))

(defun git-setup-log-buffer (buffer &optional merge-heads author-name author-email subject date msg)
  "Setup the log buffer for a commit."
  (unless git-status (error "Not in git-status buffer."))
  (let ((dir default-directory)
        (committer-name (git-get-committer-name))
        (committer-email (git-get-committer-email))
        (sign-off git-append-signed-off-by))
    (with-current-buffer buffer
      (cd dir)
      (erase-buffer)
      (insert
       (propertize
        (format "Author: %s <%s>\n%s%s"
                (or author-name committer-name)
                (or author-email committer-email)
                (if date (format "Date: %s\n" date) "")
                (if merge-heads
                    (format "Merge: %s\n"
                            (mapconcat 'identity merge-heads " "))
                  ""))
        'face 'git-header-face)
       (propertize git-log-msg-separator 'face 'git-separator-face)
       "\n")
      (when subject (insert subject "\n\n"))
      (cond (msg (insert msg "\n"))
            ((file-readable-p ".git/rebase-apply/msg")
             (insert-file-contents ".git/rebase-apply/msg"))
            ((file-readable-p ".git/MERGE_MSG")
             (insert-file-contents ".git/MERGE_MSG")))
      ; delete empty lines at end
      (goto-char (point-min))
      (when (re-search-forward "\n+\\'" nil t)
        (replace-match "\n" t t))
      (when sign-off (git-append-sign-off committer-name committer-email)))
    buffer))

(define-derived-mode git-log-edit-mode log-edit-mode "Git-Log-Edit"
  "Major mode for editing git log messages.

Set up git-specific `font-lock-keywords' for `log-edit-mode'."
  (set (make-local-variable 'font-lock-defaults)
       '(git-log-edit-font-lock-keywords t t)))

(defun git-commit-file ()
"
Commit the marked file(s), asking for a commit message.
If `git-do-push-on-commit' is non-nil will attempt to `git-push' to the remote repository as well.
"
  (interactive)
  (unless git-status (error "Not in git-status buffer."))

    (let ((buffer (get-buffer-create "*git-commit*"))
          (coding-system (git-get-commits-coding-system))
          author-name author-email subject date)
      (when (eq 0 (buffer-size buffer))

        (when (file-readable-p ".git/rebase-apply/info") (message "git-commit-file OH NO!!!")
;;  endo of commented out
;;          (with-temp-buffer
;;            (insert-file-contents ".git/rebase-apply/info");
;;            (goto-char (point-min))
;;            (when (re-search-forward "^Author: \\(.*\\)\nEmail: \\(.*\\)$" nil t)
;;              (setq author-name (match-string 1))
;;              (setq author-email (match-string 2)))
;;            (goto-char (point-min))
;;            (when (re-search-forward "^Subject: \\(.*\\)$" nil t)
;;              (setq subject (match-string 1)))
;;            (goto-char (point-min))
;;            (when (re-search-forward "^Date: \\(.*\\)$" nil t)
;;              (setq date (match-string 1))))
;;  endo of commented out

		  (message "git-commit-file OH NO!!!"))
        (git-setup-log-buffer buffer (git-get-merge-heads) author-name author-email subject date))

      (if (boundp 'log-edit-diff-function)
		  (log-edit 'git-do-commit nil '((log-edit-listfun . git-log-edit-files)
					 (log-edit-diff-function . git-log-edit-diff)) buffer 'git-log-edit-mode)
	  	  (log-edit 'git-do-commit nil 'git-log-edit-files buffer 'git-log-edit-mode))
      (setq paragraph-separate (concat (regexp-quote git-log-msg-separator) "$\\|Author: \\|Date: \\|Merge: \\|Signed-off-by: \\|\f\\|[ 	]*$"))
      (setq buffer-file-coding-system coding-system)
      (re-search-forward (regexp-quote (concat git-log-msg-separator "\n")) nil t)))

(defun git-setup-commit-buffer (commit)
  "Setup the commit buffer with the contents of COMMIT."
  (let (parents author-name author-email subject date msg)
    (with-temp-buffer
      (let ((coding-system (git-get-logoutput-coding-system)))
        (git-call-process t "log" "-1" "--pretty=medium" "--abbrev=40" commit)
        (goto-char (point-min))
        (when (re-search-forward "^Merge: *\\(.*\\)$" nil t)
          (setq parents (cdr (split-string (match-string 1) " +"))))
        (when (re-search-forward "^Author: *\\(.*\\) <\\(.*\\)>$" nil t)
          (setq author-name (match-string 1))
          (setq author-email (match-string 2)))
        (when (re-search-forward "^Date: *\\(.*\\)$" nil t)
          (setq date (match-string 1)))
        (while (re-search-forward "^    \\(.*\\)$" nil t)
          (push (match-string 1) msg))
        (setq msg (nreverse msg))
        (setq subject (pop msg))
        (while (and msg (zerop (length (car msg))) (pop msg)))))
    (git-setup-log-buffer (get-buffer-create "*git-commit*")
                          parents author-name author-email subject date
                          (mapconcat #'identity msg "\n"))))

(defun git-get-commit-files (commit)
  "Retrieve a sorted list of files modified by COMMIT."
  (let (files)
    (with-temp-buffer
      (git-call-process t "diff-tree" "-m" "-r" "-z" "--name-only" "--no-commit-id" "--root" commit)
      (goto-char (point-min))
      (while (re-search-forward "\\([^\0]*\\)\0" nil t 1)
        (push (match-string 1) files)))
    (sort files #'string-lessp)))

(defun git-read-commit-name (prompt &optional default)
  "Ask for a commit name, with completion for local branch, remote branch and tag."
  (completing-read prompt
                   (list* "HEAD" "ORIG_HEAD" "FETCH_HEAD" (mapcar #'car (git-for-each-ref)))
		   nil nil nil nil default))

(defun git-checkout (branch &optional merge)
  "Checkout a branch, tag, or any commit.
Use a prefix arg if git should merge while checking out."
  (interactive
   (list (git-read-commit-name "Checkout: ")
         current-prefix-arg))
  (unless git-status (error "Not in git-status buffer."))
  (apply 'git-call-process-string  "fetch" "origin" branch  () )
  (let ((args (list branch "--")))
    (when merge (push "-m" args))
    (when (apply #'git-call-process-display-error "checkout" args)
      (git-update-status-files))))

(defun git-branch (branch)
  "Create a branch from the current HEAD and switch to it."
  (interactive (list (git-read-commit-name "Branch: ")))
  (unless git-status (error "Not in git-status buffer."))
  (if (git-rev-parse (concat "refs/heads/" branch))
      (if (yes-or-no-p (format "Branch %s already exists, replace it? " branch))
          (and (git-call-process-display-error "branch" "-f" branch)
               (git-call-process-display-error "checkout" branch))
        (message "Canceled."))
    (git-call-process-display-error "checkout" "-b" branch)
	(when (yes-or-no-p "push upstream? ")
	  (git-call-process-display-error "push" "-u" "origin" branch)
	  ))
    (git-refresh-ewoc-hf git-status))

(defun git-amend-commit ()
  "Undo the last commit on HEAD, and set things up to commit an
amended version of it."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (when (git-empty-db-p) (error "No commit to amend."))
  (let* ((commit (git-rev-parse "HEAD"))
         (files (git-get-commit-files commit)))
    (when (if (git-rev-parse "HEAD^")
              (git-call-process-display-error "reset" "--soft" "HEAD^")
            (and (git-update-ref "ORIG_HEAD" commit)
                 (git-update-ref "HEAD" nil commit)))
      (git-update-status-files files t)
      (git-setup-commit-buffer commit)
      (git-commit-file))))

(defun git-cherry-pick-commit (arg)
  "Cherry-pick a commit."
  (interactive (list (git-read-commit-name "Cherry-pick commit: ")))
  (unless git-status (error "Not in git-status buffer."))
  (let ((commit (git-rev-parse (concat arg "^0"))))
    (unless commit (error "Not a valid commit '%s'." arg))
    (when (git-rev-parse (concat commit "^2"))
      (error "Cannot cherry-pick a merge commit."))
    (let ((files (git-get-commit-files commit))
          (ok (git-call-process-display-error "cherry-pick" "-n" commit)))
      (git-update-status-files files ok)
      (with-current-buffer (git-setup-commit-buffer commit)
        (goto-char (point-min))
        (if (re-search-forward "^\n*Signed-off-by:" nil t 1)
            (goto-char (match-beginning 0))
          (goto-char (point-max)))
        (insert "(cherry picked from commit " commit ")\n"))
      (when ok (git-commit-file)))))

(defun git-revert-commit (arg)
  "Revert a commit."
  (interactive (list (git-read-commit-name "Revert commit: ")))
  (unless git-status (error "Not in git-status buffer."))
  (let ((commit (git-rev-parse (concat arg "^0"))))
    (unless commit (error "Not a valid commit '%s'." arg))
    (when (git-rev-parse (concat commit "^2"))
      (error "Cannot revert a merge commit."))
    (let ((files (git-get-commit-files commit))
          (subject (git-get-commit-description commit))
          (ok (git-call-process-display-error "revert" "-n" commit)))
      (git-update-status-files files ok)
      (when (string-match "^[0-9a-f]+ - \\(.*\\)$" subject)
        (setq subject (match-string 1 subject)))
      (git-setup-log-buffer (get-buffer-create "*git-commit*")
                            (git-get-merge-heads) nil nil (format "Revert \"%s\"" subject) nil
                            (format "This reverts commit %s.\n" commit))
      (when ok (git-commit-file)))))

(defun git-find-file ()
  "Visit the current file in its own buffer."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((info (ewoc-data (ewoc-locate git-status))))
    (unless (git-expand-directory info)
      (find-file (git-fileinfo->name info))
      (when (eq 'unmerged (git-fileinfo->state info))
        (smerge-mode 1)))))

(defun git-find-file-other-window ()
  "Visit the current file in its own buffer in another window."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((info (ewoc-data (ewoc-locate git-status))))
    (find-file-other-window (git-fileinfo->name info))
    (when (eq 'unmerged (git-fileinfo->state info))
      (smerge-mode))))

(defun git-find-file-imerge ()
  "Visit the current file in interactive merge mode."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((info (ewoc-data (ewoc-locate git-status))))
    (find-file (git-fileinfo->name info))
    (smerge-ediff)))

(defun git-view-file ()
  "View the current file in emacs view-mode."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((info (ewoc-data (ewoc-locate git-status))))
    (view-file (git-fileinfo->name info))))


(defvar git-current-branch nil "name of the branch from for display in ewoc")
(defvar git-local-branch-ref nil "from show ref  refs/head/<branch-name>") ;; should always exist
(defvar git-remote-branch-ref nil "from show ref  refs/remotes/origin/<branch-name>") ;; may not exist for local only branch
(defvar git-branch-name nil "the <branch-name> from the previous vars")

(defun git-set-ref-vars ()
  "set the global vars git-local-branch-ref and git-remote-branch-ref"
  (let ((resultList (split-string (apply 'git-call-process-string "show-ref" git-current-branch ()))))
	(dolist (line resultList)
	  (when (string-match-p (regexp-quote (concat "refs/heads/" git-current-branch)) line) (setq git-local-branch-ref line)  )
  	  (when (string-match-p (regexp-quote (concat "refs/remotes/origin/" git-current-branch)) line) (setq git-remote-branch-ref line)))))

(defun git-set-current-branch ()
  ""
  (setq git-current-branch nil)
  (let   ((branch (git-call-process-string "symbolic-ref" "-q" "--short" "HEAD")))
	(when branch (setq git-current-branch (replace-regexp-in-string "\n$" "" branch)))))


(defun git-refresh-status ()
  "Refresh the git status buffer."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (message "Refreshing git status...")
  (git-update-status-files)
  (message "Refreshing git status...done"))

(defun git-status-quit ()
  "Quit git-status mode."
  (interactive)
  (bury-buffer))

(defun git-r-cmds ()
  "
**** remove or revert
remove --- removes selected file(s) from the sandbox and index `git-remove-file'
revert --- reverts changes to selected file(s) `git-revert-file'
"

  (interactive)
  (let ((cmd
    (completing-read "re: "
                     '(("remove" 1) ("revert" 2) ("re-help" 3))
                     nil t "re")))
    (when (string-equal "remove" cmd) (git-remove-file))
    (when (string-equal "revert" cmd) (git-revert-file))
    (when (string-equal "re-help" cmd) (describe-function 'git-r-cmds))
    ))

(defun git-push-pull-cmds ()
  "
****  push or pull ***
push  \"git push\"          -- pushes changes to remote repository:  `git-push'
pull  \"git `git-pull-command'\" -- uses custom variable to pull from remote repository:  `git-pull'

"
  (interactive)
  (let ((cmd
    (completing-read "pu: "
                     '(("pull" 1) ("push" 2) ("pu-help" 3))
                     nil t "pu")))
    (when (string-equal "pull" cmd) (git-pull))
    (when (string-equal "push" cmd) (git-push))
    (when (string-equal "pu-help" cmd) (describe-function 'git-push-pull-cmds)))
  )



(defun git-diff-cmds ()
"
**** diff help ****
diff-git      ----  generates a git diff in patch format: `git-diff-file'
diff-ediff    ----  emacs interactive diff between selected file and HEAD: `git-diff-file-idiff'
diff-ref      ----  emacs interactive diff with symbolic ref (sha):  `git-diff-ref'

"
  (interactive)
  (let ((cmd
    (completing-read "diff-: "
                     '(("diff-help" 1)
                       ("diff-git" 2)
                       ("diff-ediff" 3)
                       ("diff-ref" 4)
                       )
                     nil t "diff-")))
    (when (string-equal "diff-help" cmd) (describe-function 'git-diff-cmds) )
    (when (string-equal "diff-git" cmd) (git-diff-file))
    (when (string-equal "diff-ediff" cmd) (git-diff-file-idiff))
    (when (string-equal "diff-ref" cmd) (call-interactively 'git-diff-ref))
    ))

(defun git-stash-cmds ()
  "
auto complete commands starting with s
  **** stash help ****
stash-save    -- stashes away current modifications to the sandbox:  `git-stash' save
stash-pop     -- applies the stashed changes to sandbox and deletes the stash if no conflicts:  `git-stash' pop
stash-drop    -- drops the stashed changs without changing the sandbox:    `git-stash' drop
stash-apply   -- apply the stashed changes to the sandbox (does not drop):    `git-stash' apply
stash-show    -- lists files saved in the stash  (git stash show <stash> )
"
  (interactive)
  (let ((cmd
    (completing-read "stash-: "
                     '(("stash-help" 1)
                       ("stash-save" 2)
                       ("stash-pop" 3)
                       ("stash-drop" 4)
                       ("stash-apply" 5)
					   ("stash-show" 6)
                       )
                     nil t "stash-")))
    (when (string-equal "stash-save" cmd) (git-stash "save"))
    (when (string-equal "stash-pop" cmd) (git-stash "pop"))
    (when (string-equal "stash-drop" cmd) (git-stash "drop"))
    (when (string-equal "stash-apply" cmd) (git-stash "apply"))
	(when (string-equal "stash-show" cmd) (git-stash "show"))
    (when (string-equal "stash-help" cmd) (describe-function 'git-stash-cmds))
      ))

;;
;; ********************************
;; Start branch support
;; ********************************
;;

(defun git-local-branches ()
  "returns list of local branches"
  (let ((results   (git-call-process-string  "branch"  ))
		(branches "")
		(final ())
		(mylist ()))
	(when (eq results nil) (error "git branch -a failed" ))
	(setq mylist (split-string results "\n" t))
	(dolist (line mylist)
	  (add-to-list 'final (substring line 2)))
	final
	)
  )

(defun git-remote-branches ()
  "returns list of remote branches"
  (let ((results   (git-call-process-string  "branch" "-r" ))
		(branches "")
		(final ())
		(mylist ()))

	(when (eq results nil) (error "git branch -a failed" ))
	(setq mylist (split-string results "\n" t))
	;; strip off the "  origin/" from each
	(dolist (line mylist) (add-to-list 'final (substring line 9)))
	final
	)
  )



(defun git-list-branches ()
  "lists local branches"
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (message  (mapconcat 'identity (git-local-branches)  "\n")))

(defun git-delete-local-branch ()
  "Deletes a local branch"
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((branch
		 (completing-read "Delete local:  "  (git-local-branches) nil nil nil nil nil)))
	(unless (eq branch nil)
	  (when (y-or-n-p (format "Are you sure you want to delete the LOCAL %s branch?" branch))
		( git-call-process-display-error "branch"  "-D" branch  )))

	)
  (message "Done")
  )

(defun git-delete-remote-branch ()
  "Deletes a remote branch"
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((branch
		 (completing-read "Delete remote:  "  (git-remote-branches) nil nil nil nil nil)))
	(unless (eq branch nil)
	  (when (y-or-n-p (format "Are you sure you want to delete the REMOTE %s branch?" branch))
		( git-call-process-display-error "push" "origin" "--delete" branch  )))

	)
  (message "Done")
  )

(defun git-list-remote-branch ()
  "lists remote branches with auto complete"
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((branch
		 (completing-read "list:  "  (git-remote-branches) nil nil nil nil nil)))

	)
  )

(defun git-branch-commands ()
  "
auto complete commands starting with B
  **** Branch help ****
Branch-help            ---   Shows the help screen
Branch-list            ---   Lists local branches
Branch-list-remote     ---   Lists remote branches (with auto-complete)
Branch-create          ---   Creates local branch
Branch-switch-to       ---   Switch to branch (with auto-complete)
Branch-delete-local    ---   Delete local branch (with auto-complete)
Branch-delete-remote   ---   Delete remote branch (with auto-complete)
"
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((cmd
		 (completing-read "Branch-: "
						  '(("Branch-help" 1)
							("Branch-list" 2)
							("Branch-create" 3)
							("Branch-switch-to" 4)
							("Branch-delete-local" 5)
							("Branch-delete-remote" 6)
							("Branch-list-remote" 7)
							)
						  nil t "Branch-")))
	(when (string-equal "Branch-help"        cmd) (describe-function 'git-branch-commands))
	(when (string-equal "Branch-list"        cmd) (git-list-branches))
	(when (string-equal "Branch-create"      cmd) (call-interactively 'git-branch))
	(when (string-equal "Branch-switch-to"   cmd) (call-interactively 'git-checkout))
	(when (string-equal "Branch-delete-local"      cmd) (call-interactively 'git-delete-local-branch))
	(when (string-equal "Branch-delete-remote"  cmd) (call-interactively 'git-delete-remote-branch))
	(when (string-equal "Branch-list-remote" cmd) (call-interactively 'git-list-remote-branch))

	)
  )



;;
;; ********************************
;; End branch support
;; ********************************
;;

;;;; Major Mode
;;;; ------------------------------------------------------------

(defvar git-status-mode-hook nil
  "Run after `git-status-mode' is setup.")

(defvar git-pull-hook nil
  "Run after `git-pull' is completed.")

(defvar git-status-mode-map nil
  "Keymap for git major mode.")

(defvar git-status nil
  "List of all files managed by the git-status mode.")

(unless git-status-mode-map
  (let ((map (make-keymap))
        (commit-map (make-sparse-keymap)))
    (suppress-keymap map t)

    (define-key map "\C-c"  commit-map)  ;; the original commit map
    (define-key map "?"     'git-help)
    (define-key map "\r"    'git-find-file)       ;; return key

    (define-key map "a"     'git-add-file)
	(define-key map "B"     'git-branch-commands) ;; set of branch commands
    (define-key map "c"     'git-commit-file)
    (define-key map "d"     'git-diff-cmds)

    (define-key map "g"     'git-refresh-status)
    (define-key map "G"     'git-user-command)
    (define-key map "h"     'git-help)
    (define-key map "H"     'git-show-view-variables)


    (define-key map "p"     'git-push-pull-cmds)
    (define-key map "P"     'git-prev-unmerged-file)
    (define-key map "N"     'git-next-unmerged-file)

    (define-key map "r"     'git-r-cmds )
    (define-key map "s"     'git-stash-cmds )

;;    (define-key map "s"   'git-insert-file)  ;; show file even if it is uptodate
;;    (define-key map "x"   'git-remove-handled)
;;    (define-key map "i"   'git-ignore-file)
    (define-key map "U"     'git-toggle-show-uptodate)  ;; show all uptodate files
    (define-key map "I"     'git-toggle-show-ignored)
    (define-key map "K"     'git-toggle-show-unknown)


    (define-key map "l"     'git-log-file)
    (define-key map "L"    'git-log-branch) ;; Show the log for the whole branch

    (define-key map "m"     'git-mark-file)
    (define-key map "\M-m"  'git-mark-all)

    (define-key map "o"     'git-find-file-other-window)
    (define-key map "q"     'git-status-quit)
    (define-key map "u"     'git-unmark-file)
    (define-key map "v"     'git-view-file)
    (define-key map "\M-u"  'git-unmark-all)




    ; the commit submap
;;    (define-key commit-map "\C-a" 'git-amend-commit)
;;    (define-key commit-map "\C-b" 'git-branch)
;;    (define-key commit-map "\C-o" 'git-checkout)
    (define-key commit-map "\C-p" 'git-cherry-pick-commit)
    (define-key commit-map "\C-v" 'git-revert-commit)

;; the diff submap  want to play with these before I decide where to put them.
;;(define-key diff-map "b" 'git-diff-file-base) Diff marked unmerged file(s) against the common base file.
;;(define-key diff-map "c" 'git-diff-file-combined);; Do combined diff of the marked unmerged file(s).
;;(define-key diff-map "E" 'git-find-file-imerge) Visit current file in emacs interactive merge mode.

;;    (define-key diff-map "h" 'git-diff-file-merge-head)
;;"Diff the marked file(s) against the first merge head (or the nth one with a numeric prefix)."

;;    (define-key diff-map "m" 'git-diff-file-mine);;
;;    (define-key diff-map "o" 'git-diff-file-other);;Diff the marked unmerged file(s) against the specified stage."


    (setq git-status-mode-map map))
  (easy-menu-define git-menu git-status-mode-map
    "Git Menu"
    `("Git"
      ["Refresh" git-refresh-status t]
      ["Commit" git-commit-file t]
      ["Checkout..." git-checkout t]
;;      ["New Branch..." git-branch t]
      ["Cherry-pick Commit..." git-cherry-pick-commit t]
      ["Revert Commit..." git-revert-commit t]
      ("Merge"
	["Next Unmerged File" git-next-unmerged-file t]
	["Prev Unmerged File" git-prev-unmerged-file t]
	["Interactive Merge File" git-find-file-imerge t]
	["Diff Against Common Base File" git-diff-file-base t]
	["Diff Combined" git-diff-file-combined t]
	["Diff Against Merge Head" git-diff-file-merge-head t]
	["Diff Against Mine" git-diff-file-mine t]
	["Diff Against Other" git-diff-file-other t])
      "--------"
      ["Add File" git-add-file t]
      ["Revert File" git-revert-file t]
      ["Ignore File" git-ignore-file t]
      ["Remove File" git-remove-file t]
      ["Insert File" git-insert-file t]
      "--------"
      ["Find File" git-find-file t]
      ["View File" git-view-file t]
      ["Diff File" git-diff-file t]
      ["Interactive Diff File" git-diff-file-idiff t]
      ["Log" git-log-file t]
      "--------"
      ["Mark" git-mark-file t]
      ["Mark All" git-mark-all t]
      ["Unmark" git-unmark-file t]
      ["Unmark All" git-unmark-all t]
      ["Toggle All Marks" git-toggle-all-marks t]
      ["Hide Handled Files" git-remove-handled t]
      "--------"
      ["Show Uptodate Files" git-toggle-show-uptodate :style toggle :selected git-show-uptodate]
      ["Show Ignored Files" git-toggle-show-ignored :style toggle :selected git-show-ignored]
      ["Show Unknown Files" git-toggle-show-unknown :style toggle :selected git-show-unknown]
      "--------"
      ["Quit" git-status-quit t])))


;; git mode should only run in the *git status* buffer
(put 'git-status-mode 'mode-class 'special)

(defun git-status-mode ()
"Major mode for interacting with Git.
The git-status buffere has a header that contains the following information:

Directory:  <the root of the local sandbox>   i.e. the top level directory containing a .git file;
Branch:     <the current branch for the sandbox>
Head:       <The log message for the HEAD of the local repository>
Status:     <The status of the local repository compared to the remote repository>  see `git-upstream-status' and H key below;
Stashes:    <list of the current set of stashes>

Key mapping in git-status-mode:
\\{git-status-mode-map}"
  (kill-all-local-variables)
  (buffer-disable-undo)
  (setq mode-name "git status"
        major-mode 'git-status-mode
        goal-column 17
        buffer-read-only t)
  (use-local-map git-status-mode-map)
  (let ((buffer-read-only nil))
    (erase-buffer)
  (let ((status (ewoc-create 'git-fileinfo-prettyprint "" "")))
    (set (make-local-variable 'git-status) status))
  (set (make-local-variable 'list-buffers-directory) default-directory)
  (make-local-variable 'git-show-uptodate)
  (make-local-variable 'git-show-ignored)
  (make-local-variable 'git-show-unknown)
  (run-hooks 'git-status-mode-hook)))

(defun git-find-status-buffer (dir)
  "Find the git status buffer handling a specified directory."
  (let ((list (buffer-list))
        (fulldir (expand-file-name dir))
        found)
    (while (and list (not found))
      (let ((buffer (car list)))
        (with-current-buffer buffer
          (when (and list-buffers-directory
                     (string-equal fulldir (expand-file-name list-buffers-directory))
		     (eq major-mode 'git-status-mode))
            (setq found buffer))))
      (setq list (cdr list)))
    found))


(defun git-status (dir)
  "Entry point into git-status mode."
  (interactive "DSelect directory: ")
  (setq dir (git-get-top-dir dir))
  (if (file-exists-p (concat (file-name-as-directory dir) ".git"))
      (let ((buffer (or (and git-reuse-status-buffer (git-find-status-buffer dir))
                        (create-file-buffer (expand-file-name "*git-status*" dir)))))
        (switch-to-buffer buffer)
        (cd dir)
        (git-status-mode)
        (git-refresh-status)
        (goto-char (point-min))
        (add-hook 'after-save-hook 'git-update-saved-file))
    (message "%s is not a git working tree." dir)))

(defun git-update-saved-file ()
  "Update the corresponding git-status buffer when a file is saved.
Meant to be used in `after-save-hook'."
  (let* ((file (expand-file-name buffer-file-name))
         (dir (condition-case nil (git-get-top-dir (file-name-directory file)) (error nil)))
         (buffer (and dir (git-find-status-buffer dir))))
    (when buffer
      (with-current-buffer buffer
        (let ((filename (file-relative-name file dir)))
          ; skip files located inside the .git directory
          (unless (string-match "^\\.git/" filename)
            (git-call-process nil "add" "--refresh" "--" filename)
            (git-update-status-files (list filename))))))))

(defun git-help ()
  "Display help for Git mode."
  (interactive)
  (describe-function 'git-status-mode)
  );;; change this to display in the help buffer...

;;The format of the refspec is an optional +, followed by <src>:<dst>
;;    <src> is the pattern for references on the remote side
;;    <dst> is where those references will be written locally.
;;    The + tells Git to update the reference even if it isn’t a fast-forward.
(defun git-pull ()
  "issues:  git pull command "
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (unless git-remote-branch-ref (error "No upstream branch"))
  (unless (y-or-n-p (format "Are you sure you want to pull? ")) (error ""))
  (let ((ok nil)
		(gitcmd (concat  git-pull-command  "origin " git-local-branch-ref ":" git-remote-branch-ref)))
	(setq ok (apply 'git-call-process-display-error  (split-string gitcmd)))

	(when ok
	  (run-hooks 'git-pull-hook)
	  (message "Done!")
	  (git-update-status-files))))

(defun git-push ()
  "issues:  \"git push\""
  (interactive)
  (unless git-status (error "Not in git-status buffer."))

  (let ((ok "ok")
		(branch (git-symbolic-ref "HEAD"))
		(stat ""))

	(setq stat (git-upstream-status branch))

	(message stat)
	(when (equal stat "Local Only") (return))
	(when (not (equal stat "Up to date")) (error "Not up to date with remote branch"))
	(if (y-or-n-p (format "Are you sure you want to push? "))
		(setq ok (git-call-process-display-error  "push" "origin" "HEAD"))
	    (setq ok nil))

	(when ok (message "Done!") (git-update-status-files)  )
	(when (not ok) (message "Failed"))))



(defun git-stash (cmd)
  "Executes the command:  git stash <cmd>"
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (cond
     ( (string-equal cmd "save")
       (message (git-call-process-string-display-error "stash" cmd (read-string "description:  " nil nil "" nil))))

     ( t ;;(string-equal cmd "apply")
       (message
          (git-call-process-string-display-error
           "stash" cmd (first (split-string (completing-read "Stash: " (split-string (git-list-stash) "\n" t nil) nil t "stash@{") ":" t nil)))))

     ( (y-or-n-p (format "Are you sure you want to %s a stash? " cmd))
       (message (git-call-process-string-display-error "stash" cmd)) ))
    (git-update-status-files)
)

(defun git-upstream-status (branch-ref)
"
Returns a string showing the status of the current sandbox to the remote repository.
\"Uptodate\" means the local repository is uptodate with the remote repository
\"Unchecked\" means the remote repository is not being checked for changes, see `git-check-remote-repo'.
\"Other OOD\" means some branch other than the current branch has changed in the remote repository.
\"Current OOD\" means the current branch has changed in the remote repository.
\"Detached HEAD\" means the current sandbox is in git's \"detached head\" state and remote status is meaningless.
\"Local Only\" means there is no remote/upstream branch.
\"Unvailable\" means the attempt to contact the remote git repository failed.   See the *Messages* buffer for the command that failed.
"
    (unless git-status (error "Not in git-status buffer."))
;; note branch is a ref to a branch not simply the name.  i.e. "refs/heads/papaya" or similar
    (cond
        ( (not git-check-remote-repo) (propertize "Unchecked" 'face 'git-sandbox-status-yellow) )
        ( (not branch-ref) (propertize "DETACHED HEAD" 'face 'git-sandbox-status-yellow))
        ( (and branch-ref git-check-remote-repo)
          (let ((bname nil)
				(refs nil)
				(cnt 0)
				(statusRv nil)
                (uptodate-str "up to date")
                (UptodateSt (propertize "Up to date" 'face 'git-sandbox-status-green))
                (OtherOodSt (propertize "Other OOD" 'face 'git-sandbox-status-yellow))
                (CurOodSt (propertize "Current OOD" 'face 'git-sandbox-status-red))
                (UnavailSt (propertize "Unavailable" 'face 'git-sandbox-status-red))
				(LocalOnlySt (propertize "Local Only" 'face 'git-sandbox-status-yellow))
                )
			(setq statusRv UnavailSt);; default is unavailable
			(setq bname (if (string-match "^refs/heads/" branch-ref) (substring branch-ref (match-end 0)) branch-ref))
			(setq refs  (concat branch-ref ":refs/remotes/origin/" bname))
			(setq results (apply 'git-call-process-string  "show-ref" (concat "heads/"bname) (concat "origin/" bname)() ))

			(setq cnt (length (remove "" (split-string results "\n"))))

			(when (= cnt 0) (setq statusRv UnavailSt))
			(when (= cnt 1) (setq statusRv LocalOnlySt) )

;;			(message (concat "mbc:" results ":" branch-ref ":"))
			(when (= cnt 2)
			  (setq results (apply 'git-call-process-string  "fetch" "--no-tags" "origin" refs "--dry-run" "-v" () ))
			  (if (eq results nil)
				(setq statusRv  UnavailSt) ;; true case
			    (let (  (mylist ()) ) ;; false case

				  (setq mylist (split-string results "\n" t))
				  (setq mylist (delete (first mylist) mylist));; the first line is the "from" line

				  (dolist (line mylist)
					(if (string-match uptodate-str line)
						(setq statusRv UptodateSt)
					    (setq statusRv CurOodSt))  ))));; whent cnt is 2

			(when (> cnt 2) (setq statusRv UnavailSt))

			statusRv ;; the value of the function
			))))




(defun git-sandbox-uptodate ()
  "returns non-nil if sandbox is up-to-date"
  (message "git fetch --dry-run..." )
  ;; Most of the processing here is because fetch doesn't seem to have a way to query
  ;; a single branch... Idiotic tool that it is.
  (let (
        (results   (apply 'git-call-process-string  "fetch" "--dry-run" "-v" () ))
        (branch (git-symbolic-ref "HEAD"))
        (bname  "")
        (uptodate "up to date")
        (mylist ())
        (rv nil)
        )

    (message "git fetch --dry-run -v...Done" )
    (setq bname  (if branch
                     (if (string-match "^refs/heads/" branch)
                         (substring branch (match-end 0))
                       branch)
                   "none (detached HEAD)"))

    (setq mylist (split-string results "\n" t))

    (dolist (line mylist)
        (if (not ( eq (string-match bname line) nil))
            (setq rv line) ))

    (string-match  uptodate rv)
    )
)

(defun git-list-stash ()
    "return the output from git stash list as a string"
  (interactive)
;;  (unless git-status (error "Not in git-status buffer."))
  (apply 'git-call-process-string  "stash" "list"  () ))

(defcustom myGitRev "HEAD"
  "git revision for diffs"
  :type 'string)



;; prompts for pathname to file relative to top level git directory
;; prompts for revision which can be particular revision shuch as HEAD or HEAD-1 or the SHA1 of the commit
;; revision can also specify the HEAD of a different branch
(defun git-diff-ref()
"
Custom func for seeing diffs between one source file under git control with a specific version or HEAD.
The revision specified is saved and will become the default for the next invocation.
"
    (interactive)
    (setq myGitRev (read-string (concat "git revision[" myGitRev "]:") nil nil myGitRev  nil))
    (let ( (relpath "")
           (info (ewoc-data (ewoc-locate git-status)))
           (bufmode nil) )
         (setq relpath (git-fileinfo->name info))
         (git-call-process (concat (file-name-nondirectory relpath) ":" myGitRev) "--no-pager" "cat-file" "-p" (concat myGitRev ":" relpath) )
         (find-file-existing relpath)
         (setq bufmode (with-current-buffer (file-name-nondirectory relpath) major-mode))

         (with-current-buffer
             (concat (file-name-nondirectory relpath) ":" myGitRev)
             (funcall bufmode) )

         (ediff-buffers (file-name-nondirectory relpath) (concat (file-name-nondirectory relpath) ":" myGitRev))))

(defun git-simple-parser (inputStr)
  "returns a list of tokens from the inputStr.  Separator is space, double quotes delimit tokens with spaces, no escape characters "
  (let ((inQuote nil)
      (splitstrl (split-string inputStr " " t nil))
      (quotedStr "")
      (newlist (list) )
      (el-not-done t))
      (dolist (element splitstrl)
              (when (string-prefix-p "\"" element)
                    (setq quotedStr (concat quotedStr element ))
                    (setq inQuote t)
                    (setq el-not-done nil))

               (when (string-suffix-p "\"" element)
                     (setq inQuote nil)
                     (if el-not-done (setq quotedStr (concat quotedStr " " element)))
                     (setq el-not-done nil))

               (if (string-equal "" quotedStr)
                   (add-to-list 'newlist element t)
                   (if el-not-done (setq quotedStr (concat quotedStr " " element))))

               (when (string-suffix-p "\"" quotedStr)
                     (add-to-list 'newlist (substring quotedStr 1 -1) t)
                     (setq quotedStr ""))

               (setq el-not-done t)
               (message quotedStr))
         newlist))

(defun git-user-command ()
"
Prompts for a git command, displays the output (stdout and stderr) in the *git-log* buffer.
Returns to the updated git-status window.  Allows users to issue more complicated git commands.
Subject to the limitations of `git-simple-parser'.
"
    (interactive)
    (unless git-status (error "Not in git-status buffer."))
    (let ((cmd-string (read-string "git --no-pager " nil "status"))
          (saved-buffer (buffer-name)))
         (when (get-buffer-create "*git-usr-log*")
               (switch-to-buffer (get-buffer "*git-usr-log*"))
               (goto-char (point-max))
			   (insert "\n**********\n")
			   (insert (git-symbolic-ref "HEAD") "\n")
               (insert "git --no-pager " cmd-string "\n")
               (apply 'call-process "git" nil '(t t) t (append '("--no-pager")(git-simple-parser cmd-string)))
               (goto-char (point-max))
               (setq cmd-string (read-string "return to continue" nil ""))
               )
         (switch-to-buffer saved-buffer)
         (git-update-status-files)))

;; must be a way to call help-setup-xref without a parameter, but I couldn't figure it out.
(defun git-show-view-variables (&optional string)
"Displays the values of booleans which affect how the git status buffer displays sandbox information."
(interactive)
( let ((cb (current-buffer)))
      (setq string "")
      (with-help-window (help-buffer)
             (help-setup-xref (list #'git-show-view-variables string) (called-interactively-p))
             (set-buffer (help-buffer))
             (insert "The values of important git variables:  \n\n")
             (insert "The value of ") (help-insert-xref-button "git-show-uptodate"     'help-variable 'git-show-uptodate     (current-buffer)) (insert " is:  ") (insert (if git-show-uptodate "t\n" "nil\n"))
             (insert "The value of ") (help-insert-xref-button "git-show-ignored"      'help-variable 'git-show-ignored      (current-buffer)) (insert " is:  ") (insert (if git-show-ignored "t\n" "nil\n"))
             (insert "The value of ") (help-insert-xref-button "git-show-unknown"      'help-variable 'git-show-unknown      (current-buffer)) (insert " is:  ") (insert (if git-show-unknown "t\n" "nil\n"))
             (insert "The value of ") (help-insert-xref-button "git-check-remote-repo" 'help-variable 'git-check-remote-repo (current-buffer)) (insert " is:  ") (insert (if git-check-remote-repo "t\n" "nil\n"))
             (insert "The value of ") (help-insert-xref-button "git-do-push-on-commit" 'help-variable 'git-do-push-on-commit (current-buffer)) (insert " is:  ") (insert (if git-do-push-on-commit "t\n" "nil\n"))

             )
      (set-buffer cb)))


(provide 'git)
;;; git.el ends here
;; bugs
;;     git-log has an error on a sandbox with "nochanges" displayed
;; todo
;;    Should git status buffer display state of toggle vars  (show ignored, show uptodate etc)
;;
;;    decide if a "resolve merge" type of command is needed or if people are comfortable with "add" as a substitute
;;
;;    review the terminology throughout  (sandbox, index, local repo, remote repo)
;;
;;    branch improvements   i.e. browse local and remote branches
;;
;;    add a help command which lists the interactive git commands that I have cut out so
;;    they can be accessed with M-x git-XXXX
;;
;;  Suggest creating a global gitignore file wiht ".#\*" as an entry to avoid showing emacs lock files
;;
;;  consider moving the capitol commands to C-x <letter> and add a command to
;;  display the various vars I look at frequently.
;;
;;  The way BSC manages the sprint branch means the sprint branch is not uniformly moving
;;  forward and causes a problem.  The problem is like this:
;;  I'm working away in by sandbox based on sprint...  and commit a few changes.
;;  Now the sprint concludes without my changes...  a few items are flagged as problems in the sprint.
;;  Only the changes which didn't cause problems are pushed to master.
;;  The old sprint branch is deleted and a new branch, also named sprint, is created off of master.
;;  When I look at the state of sprint, I will see the changes I committed as differences AND the
;;  changes that didn't make it to master.  The only way to deal with this is to hold my changes
;; in stashes and not commit any changes until I'm very likely to commit.  (And even then save
;; them as stashes).  Every time the "new" sprint branch is created, I have to do a hard reset.
;; Then "diverged" always means do a hard reset.
;; git fetch origin sprint    gets the FETCH_HEAD
;; git merge-base --is-ancestor origin/sprint sprint *** MIGHT work as long as there are no local
;; commits.
;; git reset --hard FETCH_HEAD
;;  Might need to switch to sprint branch again after that.

;;  The command
