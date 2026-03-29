#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <libssh/libssh.h>
#include <libssh/sftp.h>

/* ====================================================
   Internal structs
   ==================================================== */

typedef struct {
    ssh_session session;
} NLSS_Session;

typedef struct {
    ssh_channel channel;
    SV         *session_sv;   /* holds a ref to the session SV — prevents GC */
} NLSS_Channel;

typedef struct {
    sftp_session sftp;
    SV          *session_sv;
} NLSS_SFTP;

/* ====================================================
   Helper functions
   ==================================================== */

static void
nlss_croak_error(pTHX_ ssh_session session, const char *prefix)
{
    const char *msg = ssh_get_error(session);
    Perl_croak(aTHX_ "%s: %s", prefix, msg ? msg : "(unknown error)");
}

static SV *
nlss_channel_slurp(pTHX_ ssh_channel ch, int is_stderr)
{
    SV *buf = newSVpvs("");
    char tmp[4096];
    int n;
    while (1) {
        n = ssh_channel_read(ch, tmp, sizeof(tmp), is_stderr);
        if (n <= 0)
            break;
        sv_catpvn(buf, tmp, n);
    }
    return buf;
}

MODULE = Net::LibSSH    PACKAGE = Net::LibSSH

PROTOTYPES: DISABLE

SV *
new(class)
    SV *class
  CODE:
    NLSS_Session *s;
    SV *sv;
    Newxz(s, 1, NLSS_Session);
    s->session = ssh_new();
    if (!s->session) {
        Safefree(s);
        Perl_croak(aTHX_ "Net::LibSSH::new: ssh_new() returned NULL");
    }
    sv = newSV(0);
    sv_setiv(sv, (IV) s);
    RETVAL = sv_bless(newRV_noinc(sv), gv_stashpvs("Net::LibSSH", GV_ADD));
  OUTPUT:
    RETVAL

void
DESTROY(self)
    NLSS_Session *self
  CODE:
    if (self->session) {
        ssh_disconnect(self->session);
        ssh_free(self->session);
        self->session = NULL;
    }
    Safefree(self);

void
option(self, key, value)
    NLSS_Session *self
    const char   *key
    SV           *value
  CODE:
    int rc = SSH_OK;
    if (strcmp(key, "host") == 0) {
        rc = ssh_options_set(self->session, SSH_OPTIONS_HOST, SvPV_nolen(value));
    } else if (strcmp(key, "user") == 0) {
        rc = ssh_options_set(self->session, SSH_OPTIONS_USER, SvPV_nolen(value));
    } else if (strcmp(key, "port") == 0) {
        unsigned int port = (unsigned int) SvUV(value);
        rc = ssh_options_set(self->session, SSH_OPTIONS_PORT, &port);
    } else if (strcmp(key, "knownhosts") == 0) {
        rc = ssh_options_set(self->session, SSH_OPTIONS_KNOWNHOSTS, SvPV_nolen(value));
    } else if (strcmp(key, "timeout") == 0) {
        long t = (long) SvIV(value);
        rc = ssh_options_set(self->session, SSH_OPTIONS_TIMEOUT, &t);
    } else if (strcmp(key, "compression") == 0) {
        rc = ssh_options_set(self->session, SSH_OPTIONS_COMPRESSION, SvPV_nolen(value));
    } else if (strcmp(key, "log_verbosity") == 0) {
        int v = SvIV(value);
        rc = ssh_options_set(self->session, SSH_OPTIONS_LOG_VERBOSITY, &v);
    } else if (strcmp(key, "strict_hostkeycheck") == 0) {
        int v = SvTRUE(value) ? 1 : 0;
        rc = ssh_options_set(self->session, SSH_OPTIONS_STRICTHOSTKEYCHECK, &v);
    } else {
        Perl_croak(aTHX_ "Net::LibSSH::option: unknown option '%s'", key);
    }
    if (rc != SSH_OK)
        nlss_croak_error(aTHX_ self->session, "Net::LibSSH::option");

int
connect(self)
    NLSS_Session *self
  CODE:
    RETVAL = (ssh_connect(self->session) == SSH_OK) ? 1 : 0;
  OUTPUT:
    RETVAL

void
disconnect(self)
    NLSS_Session *self
  CODE:
    ssh_disconnect(self->session);

SV *
error(self)
    NLSS_Session *self
  CODE:
    const char *msg = ssh_get_error(self->session);
    RETVAL = (msg && *msg) ? newSVpv(msg, 0) : &PL_sv_undef;
  OUTPUT:
    RETVAL

int
auth_password(self, password)
    NLSS_Session *self
    const char   *password
  CODE:
    RETVAL = (ssh_userauth_password(self->session, NULL, password)
              == SSH_AUTH_SUCCESS) ? 1 : 0;
  OUTPUT:
    RETVAL

int
auth_agent(self)
    NLSS_Session *self
  CODE:
    int rc = ssh_userauth_agent(self->session, NULL);
    if (rc != SSH_AUTH_SUCCESS)
        rc = ssh_userauth_publickey_auto(self->session, NULL, NULL);
    RETVAL = (rc == SSH_AUTH_SUCCESS) ? 1 : 0;
  OUTPUT:
    RETVAL

int
auth_publickey(self, privkey_path)
    NLSS_Session *self
    const char   *privkey_path
  CODE:
    ssh_key key = NULL;
    int rc = ssh_pki_import_privkey_file(privkey_path, NULL, NULL, NULL, &key);
    if (rc != SSH_OK) {
        RETVAL = 0;
    } else {
        rc = ssh_userauth_publickey(self->session, NULL, key);
        ssh_key_free(key);
        RETVAL = (rc == SSH_AUTH_SUCCESS) ? 1 : 0;
    }
  OUTPUT:
    RETVAL

SV *
channel(self)
    NLSS_Session *self
  CODE:
    ssh_channel ch = ssh_channel_new(self->session);
    if (!ch)
        XSRETURN_UNDEF;
    if (ssh_channel_open_session(ch) != SSH_OK) {
        ssh_channel_free(ch);
        XSRETURN_UNDEF;
    }
    NLSS_Channel *c;
    Newxz(c, 1, NLSS_Channel);
    c->channel    = ch;
    c->session_sv = SvREFCNT_inc(ST(0));
    SV *sv = newSV(0);
    sv_setiv(sv, (IV) c);
    RETVAL = sv_bless(newRV_noinc(sv), gv_stashpvs("Net::LibSSH::Channel", GV_ADD));
  OUTPUT:
    RETVAL

SV *
sftp(self)
    NLSS_Session *self
  CODE:
    sftp_session sftp = sftp_new(self->session);
    if (!sftp)
        XSRETURN_UNDEF;
    if (sftp_init(sftp) != SSH_OK) {
        sftp_free(sftp);
        XSRETURN_UNDEF;
    }
    NLSS_SFTP *s;
    Newxz(s, 1, NLSS_SFTP);
    s->sftp       = sftp;
    s->session_sv = SvREFCNT_inc(ST(0));
    SV *sv = newSV(0);
    sv_setiv(sv, (IV) s);
    RETVAL = sv_bless(newRV_noinc(sv), gv_stashpvs("Net::LibSSH::SFTP", GV_ADD));
  OUTPUT:
    RETVAL


MODULE = Net::LibSSH    PACKAGE = Net::LibSSH::Channel

void
DESTROY(self)
    NLSS_Channel *self
  CODE:
    if (self->channel) {
        ssh_channel_send_eof(self->channel);
        ssh_channel_close(self->channel);
        ssh_channel_free(self->channel);
        self->channel = NULL;
    }
    SvREFCNT_dec(self->session_sv);
    Safefree(self);

int
exec(self, cmd)
    NLSS_Channel *self
    const char   *cmd
  CODE:
    RETVAL = (ssh_channel_request_exec(self->channel, cmd) == SSH_OK) ? 1 : 0;
  OUTPUT:
    RETVAL

SV *
read(self, ...)
    NLSS_Channel *self
  CODE:
    int is_stderr = 0;
    int len       = -1;
    if (items >= 2) len       = SvIV(ST(1));
    if (items >= 3) is_stderr = SvTRUE(ST(2));
    if (len < 0) {
        RETVAL = nlss_channel_slurp(aTHX_ self->channel, is_stderr);
    } else {
        char *buf;
        int   n;
        Newx(buf, len + 1, char);
        n = ssh_channel_read(self->channel, buf, len, is_stderr);
        if (n <= 0) {
            Safefree(buf);
            RETVAL = newSVpvs("");
        } else {
            RETVAL = newSVpvn(buf, n);
            Safefree(buf);
        }
    }
  OUTPUT:
    RETVAL

int
write(self, data)
    NLSS_Channel *self
    SV           *data
  CODE:
    STRLEN      len;
    const char *ptr = SvPV(data, len);
    RETVAL = ssh_channel_write(self->channel, ptr, (uint32_t) len);
  OUTPUT:
    RETVAL

void
send_eof(self)
    NLSS_Channel *self
  CODE:
    ssh_channel_send_eof(self->channel);

int
eof(self)
    NLSS_Channel *self
  CODE:
    RETVAL = ssh_channel_is_eof(self->channel);
  OUTPUT:
    RETVAL

int
exit_status(self)
    NLSS_Channel *self
  CODE:
    RETVAL = ssh_channel_get_exit_status(self->channel);
  OUTPUT:
    RETVAL

void
close(self)
    NLSS_Channel *self
  CODE:
    if (self->channel) {
        ssh_channel_send_eof(self->channel);
        ssh_channel_close(self->channel);
        ssh_channel_free(self->channel);
        self->channel = NULL;
    }


MODULE = Net::LibSSH    PACKAGE = Net::LibSSH::SFTP

void
DESTROY(self)
    NLSS_SFTP *self
  CODE:
    if (self->sftp) {
        sftp_free(self->sftp);
        self->sftp = NULL;
    }
    SvREFCNT_dec(self->session_sv);
    Safefree(self);

SV *
stat(self, path)
    NLSS_SFTP  *self
    const char *path
  CODE:
    sftp_attributes attr = sftp_stat(self->sftp, path);
    if (!attr)
        XSRETURN_UNDEF;
    HV *h = newHV();
    hv_stores(h, "name",  newSVpv(attr->name ? attr->name : path, 0));
    hv_stores(h, "size",  newSVuv(attr->size));
    hv_stores(h, "uid",   newSVuv(attr->uid));
    hv_stores(h, "gid",   newSVuv(attr->gid));
    hv_stores(h, "mode",  newSVuv(attr->permissions));
    hv_stores(h, "atime", newSVuv(attr->atime64 ? attr->atime64 : attr->atime));
    hv_stores(h, "mtime", newSVuv(attr->mtime64 ? attr->mtime64 : attr->mtime));
    sftp_attributes_free(attr);
    RETVAL = newRV_noinc((SV *) h);
  OUTPUT:
    RETVAL
