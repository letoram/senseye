/*
 * Copyright 2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator works on popen: on stepframe it runs
 * the command that is set as the chain opener (which should work on
 * a pipes and filters basis) in order to classify and output a string
 * that describes the format of the current buffer.
 */
#include "xlt_supp.h"
#include "font_8x8.h"

#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <poll.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>

static int glob_argc;
static char** glob_argv;

struct xlt_session {
	struct arcan_shmif_cont in;
	struct arcan_shmif_cont out;
};

static bool poll_inp(int pfd, char* buf, size_t* ofs, size_t* sz)
{
	short pollev = POLLIN | POLLERR | POLLHUP | POLLNVAL;
	struct pollfd fds[1] = {
		{.fd = pfd, .events = pollev}
	};

	int pc = poll(fds, 1, 1);

	if (pc <= 0)
		return true;

	if ((fds[0].revents & POLLIN) > 0){
		ssize_t nr = read(pfd, &buf[*ofs], *sz - *ofs);

		if (-1 == nr)
			return errno == EAGAIN;

		*ofs += nr;
		if (*ofs == *sz)
			return false;
	}

	if ((fds[0].revents & ~POLLIN) > 0)
		return false;

	return true;
}

static char* pipe_step(size_t inbuf_sz, size_t out_sz, uint8_t* buf)
{
	int in[2];
	int out[2];

	pipe(in);
	pipe(out);

	pid_t pid;
	if ( (pid = fork()) ){
		close(in[1]);
		close(out[0]);

		size_t out_ofs = 0;
		int rc;

/* some minor buffering */
		size_t inbuf_ofs = 0;
		char inbuf[ inbuf_sz + 1 ];
		memset(inbuf, '\0', inbuf_sz + 1);

		bool failed = false;
/* naive flush */
		while (out_sz - out_ofs > 0 && !failed){
			ssize_t nw = write(out[1], &buf[out_ofs], out_sz-out_ofs);
			if (-1 == nw)
				break;

			out_ofs += nw;
			failed = poll_inp(in[0], inbuf, &inbuf_ofs, &inbuf_sz);
		}

		close(out[1]);
		while(!failed && poll_inp(in[0], inbuf, &inbuf_ofs, &inbuf_sz));

/* get rid of the child, we are done here */
		kill(pid, SIGKILL);
		waitpid(pid, &rc, WNOHANG);

/* font rendering will filter possibly weird characters */
		inbuf[inbuf_ofs] = '\0';
		return strdup(inbuf);
	}
/* skip first argument, copy rest and null terminate */
	else if (-1 == pid)
		fprintf(stderr, "fork failed, reason: %s\n", strerror(errno));
	else {
		char* nargv[glob_argc+1];
		for (size_t i = 0; i < glob_argc; i++)
			nargv[i] = glob_argv[i];
		nargv[glob_argc] = NULL;

		close(in[0]);
		close(out[1]);
		close(STDIN_FILENO);
		close(STDOUT_FILENO);
		dup2(in[1], STDOUT_FILENO);
		dup2(out[0], STDIN_FILENO);

		if (-1 == execv(glob_argv[0], nargv))
			exit(EXIT_FAILURE);
	}

	return NULL;
}

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	if (!buf){
		free(out->user);
		return false;
	}

	if (!out->user){
		arcan_shmif_resize(out, 512, 32);
		draw_box(out, 0, 0, out->addr->w,
			out->addr->h, RGBA(0x00, 0x00, 0x00, 0xff));
		arcan_shmif_signal(out, SHMIF_SIGVID);
	}

	size_t inbuf_sz = (out->addr->w / fontw) * (out->addr->h / fonth);
	char* msg = pipe_step(inbuf_sz, buf_sz, buf);
	draw_box(out, 0, 0, out->addr->w,
		out->addr->h, RGBA(0x00, 0x00, 0x00, 0xff));

	if (msg){
		draw_text(out, msg, 2, 2, RGBA(0xff, 0xff, 0xff, 0xff));
		free(msg);
		return true;
	}

	return true;
}

int main(int argc, char* argv[])
{
	char name[32];
	snprintf(name, 32, "DPIPE(%d)", (int) getpid());

	glob_argc = argc - 1;
	glob_argv = &argv[1];

	signal(SIGPIPE, SIG_IGN);

	return xlt_setup(name, populate, NULL, XLT_NONE) == true ?
		EXIT_SUCCESS : EXIT_FAILURE;
}
